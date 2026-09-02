library(shiny)
library(bslib)
library(reticulate)
library(shinyjs)

# Python back-end script
source_python("chatbot_for_integration.py")

# Custom theme with your color palette
custom_theme <- bs_theme(
  bg = "white",
  fg = "black",
  primary = "#004aab",
  secondary = "#3a76d8",
  success = "#1d6522",
  warning = "#F16125",
  danger = "#F16125",
  info = "#3a76d8",
  base_font = font_google("Source Sans Pro")
)

CHAT_STORE <- new.env(parent = emptyenv())

get_history <- function(sid) {
  if (exists(sid, envir = CHAT_STORE, inherits = FALSE)) {
    get(sid, envir = CHAT_STORE, inherits = FALSE)
  } else {
    list(list(
      sender = "bot",
      message = paste(
        "Hi! I'm your Knowledge Base assistant. I answer questions from the",
        "PA Knowledge Base docs, which are vectorized and stored in Qdrant.",
        "Ask me anything knowledge-base related!"
      )
    ))
  }
}

set_history <- function(sid, hist) {
  assign(sid, hist, envir = CHAT_STORE)
}

# Per-tab UI preferences (currently just dark mode), keyed by the same sid as
# CHAT_STORE. Like the chat history, this lives only for the life of the R
# process but survives a Quarto page switch (which reloads the iframe).
PREFS_STORE <- new.env(parent = emptyenv())

get_prefs <- function(sid) {
  if (nzchar(sid) && exists(sid, envir = PREFS_STORE, inherits = FALSE)) {
    get(sid, envir = PREFS_STORE, inherits = FALSE)
  } else {
    list(dark_mode = FALSE)
  }
}

set_prefs <- function(sid, prefs) {
  if (nzchar(sid)) assign(sid, prefs, envir = PREFS_STORE)
}

# Strip the handful of markup vectors commonmark passes through from raw HTML
# in the model's reply (defence in depth — the corpus is internal).
sanitize_html <- function(html) {
  html <- gsub("(?is)<\\s*(script|style|iframe|object|embed|form|meta|link)\\b.*?(</\\s*\\1\\s*>|$)",
               "", html, perl = TRUE)
  html <- gsub("(?i)\\son[a-z]+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)", "",
               html, perl = TRUE)
  html <- gsub("(?i)(href|src)\\s*=\\s*(\"\\s*(javascript|vbscript|data):[^\"]*\"|'\\s*(javascript|vbscript|data):[^']*')",
               '\\1="#"', html, perl = TRUE)
  html
}

# Post-process commonmark's <a href="..."> tags:
#   * every link gets target="_top" so the click escapes the chatbot iframe;
#   * a site-relative citation path (one of `known`, or anything under site/)
#     is resolved to an absolute URL under `origin` and marked
#     .chat-inline-link.
# `known` is the exact list of source paths handed to the LLM in the prompt
# (already .html + URL-encoded at ingestion), so no cleaning is needed here.
# Returns list(html, used = <known paths that appeared as links>).
resolve_anchors <- function(html, known, origin) {
  used <- character()
  m <- gregexpr('<a href="([^"]*)">(.*?)</a>', html, perl = TRUE)[[1]]
  if (length(m) == 1 && m[1] == -1) return(list(html = html, used = used))
  cs <- attr(m, "capture.start")
  cl <- attr(m, "capture.length")
  starts <- as.integer(m)
  lens <- attr(m, "match.length")
  out <- ""
  prev <- 1L
  for (i in seq_along(starts)) {
    st <- starts[i]
    en <- st + lens[i] - 1L
    href <- substr(html, cs[i, 1], cs[i, 1] + cl[i, 1] - 1L)
    text <- substr(html, cs[i, 2], cs[i, 2] + cl[i, 2] - 1L)
    # commonmark HTML-escapes "&" in the target; undo it so the path matches
    # the payload URLs (which keep "&" literal, as Quarto serves it).
    rel <- gsub("&amp;", "&", sub("^\\./", "", sub("^/", "", href)), fixed = TRUE)
    is_site <- rel %in% known || grepl("^site/.+\\.html", rel)
    is_ext <- grepl("^(https?:|mailto:|tel:)", href, ignore.case = TRUE)
    if (is_site) {
      if (rel %in% known) used <- union(used, rel)
      abs_url <- if (nzchar(origin)) paste0(origin, "/", rel) else paste0("/", rel)
      new_href <- gsub("&", "&amp;", abs_url, fixed = TRUE)  # valid attribute
      rep <- sprintf(
        '<a href="%s" target="_top" rel="noopener" class="chat-inline-link">%s</a>',
        new_href, text)
    } else if (is_ext || startsWith(href, "#")) {
      rep <- sprintf('<a href="%s" target="_top" rel="noopener noreferrer">%s</a>',
                     href, text)
    } else {
      # Degenerate target the model invented, e.g. [GraphGPT](GraphGPT) — keep
      # the words, drop the broken link.
      rep <- text
    }
    out <- paste0(out, substr(html, prev, st - 1L), rep)
    prev <- en + 1L
  }
  list(html = paste0(out, substr(html, prev, nchar(html))), used = used)
}

# Render a bot reply as Markdown (fenced code, lists, links, bold ...). Source
# citations are already real Markdown links (the LLM copies them verbatim from
# the prompt, built from the Qdrant payload); here we only resolve their
# site-relative target against `origin` and make every link escape the iframe.
#
# Returns list(html = <tag>, linked = <int vector of indices into `sources`
# that were linked inline>) so the caller can drop those from the "Sources:"
# fallback row.
render_bot_message <- function(text, sources, origin) {
  if (is.null(text) || length(text) != 1 || is.na(text) || !nzchar(text)) {
    return(list(html = p(text), linked = integer()))
  }

  paths <- vapply(sources, function(s) {
    if (is.null(s$path)) "" else s$path
  }, character(1))

  md <- gsub("\r\n", "\n", text, fixed = TRUE)
  html <- tryCatch(
    commonmark::markdown_html(md, hardbreaks = TRUE, extensions = TRUE),
    error = function(err) NULL
  )
  if (is.null(html)) {
    esc <- gsub("\n", "<br/>", htmltools::htmlEscape(md), fixed = TRUE)
    return(list(html = HTML(esc), linked = integer()))
  }

  res <- resolve_anchors(sanitize_html(html), paths[nzchar(paths)], origin)
  linked <- which(paths %in% res$used)
  list(html = div(class = "bot-md", HTML(res$html)), linked = linked)
}

ui <- page_fluid(

  theme = custom_theme,

  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      style = "background-color: #004aab; color: white;",
      "Chat Window",
      tags$div(
        class = "dropdown",
        tags$button(
          class = "btn btn-sm text-white border-0 p-0 lh-1",
          style = "background: none; font-size: 1.2rem;",
          `data-bs-toggle` = "dropdown",
          `data-bs-auto-close` = "outside",
          `aria-expanded` = "false",
          `aria-label` = "Settings",
          HTML("&#9881;")  # gear
        ),
        tags$div(
          class = "dropdown-menu dropdown-menu-end shadow border-0 p-0",
          style = "min-width: 0; width: max-content; max-width: 195px; overflow: hidden;",
          tags$div(
            class = "px-3 py-1 fw-semibold small",
            style = "background-color: #004aab; color: #fff;",
            HTML("&#9881;&#65039;&nbsp; Settings")
          ),
          tags$div(
            class = "px-3 py-2",
            tags$div(
              class = "d-flex align-items-center justify-content-between gap-2",
              tags$span(class = "fw-medium", HTML("&#127769;&nbsp; Dark mode")),
              tags$span(class = "ms-2", style = "margin-right: -24px;",
                shinyWidgets::switchInput("darkMode", label = NULL, value = FALSE,
                                         onLabel = "ON", offLabel = "OFF", size = "small",
                                         onStatus = "success", offStatus = "default")
              )
            ),
            tags$div(class = "text-secondary small mt-1",
                     "Use a dark color theme.")
          )
        )
      )
    ),
    div(
      id = "chat-container",
      class = "html-fill-item",
      style = "flex: 1 1 auto; min-height: 0; overflow-y: auto;
                padding: 15px; border: 1px solid #F8B092; border-radius: 5px;",
      uiOutput("chatMessages")
    ),

    card_footer(
      div(
        class = "d-flex align-items-center",
        style = "width: 100%; gap: 0.5rem;",
        div(
          class = "flex-grow-1",
          style = "min-width: 0;",
          textInput("userMessage", "Type a message", placeholder = "Type your message here...",
                    width = "100%")
        ),
        actionButton("sendMessage", "Send", class = "btn",
                     style = "background-color: #F16125; color: white; flex: 0 0 auto; padding: 10px 20px; font-size: 1.05rem;")
      )
    )
  )
)

ui <- tagList(
  shinyjs::useShinyjs(),  # Initialize shinyjs
  tags$head(
    tags$style(HTML("
      /* Custom CSS with your color palette */
      .btn-primary { background-color: #F16125 !important; border-color: #F16125 !important; }
      .btn-success { background-color: #1d6522 !important; border-color: #1d6522 !important; }
      .radio-inline input[type='radio']:checked + span { color: #004aab; font-weight: bold; }
      /* This app is shown as the whole popup (in an iframe). Pin the chat card
         to the full viewport so it fills edge to edge with no white margin,
         regardless of bslib's own flex wrappers. */
      html, body {
        margin: 0; padding: 0;
        height: 100%;
        overflow: hidden;
      }
      .container-fluid {
        position: absolute;
        inset: 0;
        padding: 0 !important;
        max-width: none !important;
      }
      .container-fluid > .card {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        margin: 0 !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
      }
      .container-fluid > .card > .card-header,
      .container-fluid > .card > .card-footer {
        flex: 0 0 auto;
      }
      /* bslib centers the card body with auto margins, which leaves white
         above the messages and stops it filling. Pin it and let it grow. */
      .container-fluid > .card > .card-body {
        flex: 1 1 auto !important;
        margin: 0 !important;
        min-height: 0;
        display: flex;
        flex-direction: column;
        padding: 10px;
      }
      /* Prevent horizontal scrolling: grid/flex children default to a
         min-width based on their unconstrained content size, which can
         force the main panel wider than the space left by the sidebar. */
      /* The chat area has its own scrollbar; never show one on the whole
         iframe/page. */
      html, body { overflow: hidden; }
      .bslib-sidebar-layout, .bslib-sidebar-layout > .main {
        min-width: 0;
      }
      #chat-container { overflow-x: hidden; }
      #chat-container .rounded {
        overflow-wrap: break-word;
        word-break: break-word;
      }
      /* Hide the 'Type a message' label visually (kept for screen readers)
         so the Send button centers against the input box itself, not the
         label + input column together. Text is still shown via placeholder. */
      label[for='userMessage'] {
        position: absolute;
        width: 1px;
        height: 1px;
        padding: 0;
        margin: -1px;
        overflow: hidden;
        clip: rect(0, 0, 0, 0);
        white-space: nowrap;
        border: 0;
      }
      /* Shiny wraps the input in a container with a bottom margin, which
         makes the input column taller than the Send button and pushes the
         button off-center. Remove it so the flex row centers them evenly. */
      .card-footer .shiny-input-container,
      .card-footer .form-group {
        margin-bottom: 0;
      }
      /* Settings dropdown: drop the switch's default bottom margin so the
         menu wraps tightly around the label + toggle. */
      .dropdown-menu .shiny-input-container,
      .dropdown-menu .form-group {
        margin-bottom: 0;
      }
      .dropdown-menu .bootstrap-switch { margin: 0; }

      /* Inline feedback row under a bot reply */
      .rate-row {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 6px;
        margin: 2px 0 12px 4px;
        font-size: 0.8rem;
      }
      .rate-row .rate-label {
        color: #6c757d;
        margin-right: 2px;
      }
      .rate-btn {
        display: inline-flex;
        align-items: center;
        gap: 4px;
        padding: 3px 10px;
        border: 1px solid #d0d5dd;
        border-radius: 999px;
        background: #fff;
        color: #344054;
        font-size: 0.78rem;
        line-height: 1.2;
        cursor: pointer;
        transition: background-color .12s ease, border-color .12s ease;
      }
      .rate-btn:hover { background: #f2f4f7; border-color: #98a2b3; }
      .rate-btn.up:hover    { background: #e7f4ec; border-color: #1d6522; }
      .rate-btn.okay:hover  { background: #fdf3e3; border-color: #F16125; }
      .rate-btn.down:hover  { background: #fbeaea; border-color: #c0392b; }
      .rate-done {
        color: #6c757d;
        margin: 2px 0 12px 4px;
        font-size: 0.78rem;
      }

      /* Source citations under a bot reply: links back to the Quarto pages the
         answer was retrieved from. They open in the parent tab (target=_top)
         so they escape the chatbot iframe. */
      .source-row {
        display: flex;
        align-items: baseline;
        flex-wrap: wrap;
        gap: 6px;
        margin: 2px 0 10px 4px;
        font-size: 0.8rem;
      }
      .source-row .source-label {
        color: #6c757d;
        margin-right: 2px;
      }
      .source-link {
        display: inline-flex;
        align-items: center;
        max-width: 100%;
        padding: 3px 10px;
        border: 1px solid #d0d5dd;
        border-radius: 999px;
        background: #fff;
        color: #004aab;
        font-size: 0.78rem;
        line-height: 1.2;
        text-decoration: none;
        overflow-wrap: anywhere;
        transition: background-color .12s ease, border-color .12s ease;
      }
      .source-link:hover {
        background: #eef4ff;
        border-color: #3a76d8;
        text-decoration: underline;
      }
      /* Retrieved source the model also linked in the answer text. */
      .source-link.cited {
        background: #eef4ff;
        border-color: #3a76d8;
        font-weight: 600;
      }

      /* Inline source citations rendered inside the (blue) bot bubble. */
      #chat-container .chat-inline-link {
        color: #fff;
        font-weight: 600;
        text-decoration: underline;
        text-underline-offset: 2px;
      }
      #chat-container .chat-inline-link:hover { color: #ffe9df; }

      /* Markdown-rendered bot reply (headings, lists, code, links). */
      .bot-md > :first-child { margin-top: 0; }
      .bot-md > :last-child { margin-bottom: 0; }
      .bot-md p { margin: 0 0 8px; }
      .bot-md ul, .bot-md ol { margin: 0 0 8px; padding-left: 20px; }
      .bot-md li { margin: 2px 0; }
      .bot-md h1, .bot-md h2, .bot-md h3, .bot-md h4 {
        margin: 10px 0 6px;
        font-size: 1rem;
        font-weight: 700;
      }
      .bot-md a { color: #fff; }
      .bot-md code {
        background: rgba(0, 0, 0, 0.22);
        padding: 1px 5px;
        border-radius: 4px;
        font-size: 0.85em;
        word-break: normal;
        overflow-wrap: normal;
      }
      .bot-md pre {
        background: rgba(0, 0, 0, 0.28);
        color: #f5f7fa;
        padding: 10px 12px;
        border-radius: 6px;
        overflow-x: auto;
        margin: 6px 0 10px;
        font-size: 0.82rem;
        line-height: 1.4;
      }
      .bot-md pre code {
        background: none;
        padding: 0;
        color: inherit;
        white-space: pre;
        word-break: normal;
        overflow-wrap: normal;
      }
      .bot-md blockquote {
        margin: 6px 0;
        padding-left: 10px;
        border-left: 3px solid rgba(255, 255, 255, 0.4);
      }
      .bot-md table {
        border-collapse: collapse;
        margin: 6px 0;
      }
      .bot-md th, .bot-md td {
        border: 1px solid rgba(255, 255, 255, 0.35);
        padding: 3px 8px;
      }

      /* Typing indicator (three bouncing dots) shown inside a bot bubble
         while the LLM is still working. */
      .chat-typing {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 2px 0;
      }
      .chat-typing > span {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #fff;
        opacity: 0.5;
        animation: chat-typing-bounce 1.2s ease-in-out infinite;
      }
      .chat-typing > span:nth-child(2) { animation-delay: 0.2s; }
      .chat-typing > span:nth-child(3) { animation-delay: 0.4s; }
      @keyframes chat-typing-bounce {
        0%, 80%, 100% { transform: translateY(0);    opacity: 0.5; }
        40%           { transform: translateY(-5px); opacity: 1;   }
      }
    ")),
    # Persist the chat scroll position per browser tab. A Quarto page switch
    # reloads this iframe from scratch, which would otherwise reset the chat
    # to the top; instead we save scrollTop on every scroll and restore it
    # once the messages have rendered (see output$chatMessages).
    tags$script(HTML(
      "(function(){
         var KEY = 'chatScrollTop';
         (function bind(){
           var c = document.getElementById('chat-container');
           if (!c) { setTimeout(bind, 100); return; }
           if (c.dataset.scrollBound) return;
           c.dataset.scrollBound = '1';
           c.addEventListener('scroll', function(){
             try { sessionStorage.setItem(KEY, String(c.scrollTop)); } catch (e) {}
           });
         })();
       })();"
    ))
  ),
  ui
)

server <- function(input, output, session) {

  sid <- reactive({
    qs <- shiny::parseQueryString(session$clientData$url_search)
    if (!is.null(qs$sid) && nzchar(qs$sid)) qs$sid else session$token
  })

  # Origin of the Quarto page embedding this iframe (passed as ?origin= by
  # chatbot-toggle.html). Used to turn relative source paths into absolute
  # links back to the site. Empty when the app is opened outside the site.
  site_origin <- reactive({
    qs <- shiny::parseQueryString(session$clientData$url_search)
    if (!is.null(qs$origin) && nzchar(qs$origin)) sub("/+$", "", qs$origin) else ""
  })

  sid_value <- reactiveVal(NULL)
  observeEvent(sid(), { sid_value(sid()) }, once = TRUE)

  chatHistory <- reactiveVal()

  observeEvent(sid(), {
    chatHistory(get_history(sid()))
  }, once = TRUE)

  # Save to store whenever chatHistory changes (after it's initialized)
  observeEvent(chatHistory(), {
    req(sid())
    req(!is.null(chatHistory()))
    set_history(sid(), chatHistory())
  })

  # True until the first non-empty render. A Quarto tab switch reloads the
  # iframe -> new session -> this resets, so on the first render we restore
  # the saved scroll position (falling back to the bottom) exactly once.
  first_render_done <- FALSE

  session$onSessionEnded(function() {
    s <- sid_value()
    if (is.null(s) || !nzchar(s)) return()

    existed <- exists(s, envir = CHAT_STORE, inherits = FALSE)
    if (existed) rm(list = s, envir = CHAT_STORE)

    cat(sprintf("\n[cleanup] sid=%s removed=%s | remaining=%d\n",
                s, existed, length(ls(envir = CHAT_STORE))))
  })
  
  base_query <- reactiveVal("")

  # Custom dark mode theme
  dark_theme <- bs_theme(
    bg = "#272626",
    fg = "white",
    primary = "#F16125",
    secondary = "#3a76d8",
    success = "#1d6522",
    warning = "#F16125",
    danger = "#F16125",
    info = "#3a76d8",
    base_font = font_google("Source Sans Pro")
  )

  # Custom light mode theme
  light_theme <- custom_theme

  # Restore the saved dark-mode choice once, before we start persisting
  # changes, so a Quarto tab switch keeps whatever the reader had set.
  prefs_loaded <- FALSE
  observeEvent(sid(), {
    if (isTRUE(get_prefs(sid())$dark_mode)) {
      shinyWidgets::updateSwitchInput(session, "darkMode", value = TRUE)
      session$setCurrentTheme(dark_theme)  # apply now, don't wait for the round-trip
    }
    prefs_loaded <<- TRUE
  }, once = TRUE)

  observeEvent(input$darkMode, {
    if (!prefs_loaded) return()
    req(sid())
    set_prefs(sid(), list(dark_mode = isTRUE(input$darkMode)))
  }, ignoreNULL = FALSE)

  observe({
    if (isTRUE(input$darkMode)) {
      session$setCurrentTheme(dark_theme)
    } else {
      session$setCurrentTheme(light_theme)
    }
  })

  output$chatMessages <- renderUI({
    messages <- chatHistory()
    is_user <- vapply(messages, function(m) identical(m$sender, "user"), logical(1))
    last_user <- if (any(is_user)) max(which(is_user)) else NA_integer_
    message_elements <- lapply(seq_along(messages), function(i) {
      msg <- messages[[i]]
      if (identical(msg$sender, "user")) {
        div(
          class = "d-flex justify-content-end mb-2",
          id = if (!is.na(last_user) && i == last_user) "last-user-msg" else NULL,
          div(class = "rounded px-3 py-2",
              style = "background-color: #F8B092; color: black; max-width: 75%;",
              p(msg$message))
        )
      } else if (isTRUE(msg$pending)) {
        div(
          class = "d-flex justify-content-start mb-2",
          div(class = "rounded px-3 py-2",
              style = "background-color: #3a76d8;",
              div(class = "chat-typing",
                  tags$span(), tags$span(), tags$span())),
          # Runs once, when this placeholder is inserted (i.e. right after
          # the user hits Send). Brings the just-sent question to the top of
          # the window. Nothing scrolls when the answer or a rating renders.
          tags$script(HTML(
            "(function(){
               var c = document.getElementById('chat-container');
               var u = document.getElementById('last-user-msg');
               if (c && u) {
                 c.scrollTop += u.getBoundingClientRect().top
                                - c.getBoundingClientRect().top - 8;
               }
             })();"
          ))
        )
      } else {
        origin <- site_origin()
        srcs <- if (is.null(msg$sources)) list() else msg$sources

        # Bot bubble: the reply's own prose carries inline citation links
        # (the model copies them from the prompt); render_bot_message resolves
        # those against `origin`. `linked` = which sources got cited in text.
        rendered <- render_bot_message(msg$message, srcs, origin)

        # "Sources:" row lists the retrieved pages the answer drew on. Retrieval
        # is already score-gated (chatbot_for_integration.py), so these are all
        # strong matches; a weak LLM that forgets to cite the page inline still
        # gets it listed here. Pages the model *did* link in the prose are
        # emphasised.
        has_row <- length(srcs) > 0

        bubble <- div(
          class = if (isTRUE(msg$rateable) || has_row)
                    "d-flex justify-content-start mb-1"
                  else "d-flex justify-content-start mb-2",
          div(class = "rounded px-3 py-2",
              style = "background-color: #3a76d8; color: white; max-width: 75%;",
              rendered$html)
        )

        sources_row <- NULL
        if (has_row) {
          links <- lapply(seq_along(srcs), function(j) {
            s <- srcs[[j]]
            if (is.null(s$path) || !nzchar(s$path)) return(NULL)
            href <- if (nzchar(origin)) paste0(origin, "/", s$path) else paste0("/", s$path)
            label <- if (!is.null(s$label) && nzchar(s$label)) s$label else s$path
            cls <- if (j %in% rendered$linked) "source-link cited" else "source-link"
            tags$a(href = href, target = "_top", rel = "noopener",
                   class = cls, label)
          })
          links <- Filter(Negate(is.null), links)
          if (length(links) > 0) {
            sources_row <- div(
              class = "source-row",
              tags$span(class = "source-label", "Sources:"),
              do.call(tagList, links)
            )
          }
        }

        rating_row <- NULL
        if (isTRUE(msg$rateable)) {
          if (is.null(msg$rating)) {
            rate_btn <- function(value, variant, glyph, text) {
              tags$button(
                type = "button",
                class = paste("rate-btn", variant),
                `aria-label` = text,
                onclick = sprintf(
                  "Shiny.setInputValue('rate', {idx: %d, value: %d, n: Math.random()}, {priority: 'event'})",
                  i, value
                ),
                HTML(glyph), tags$span(text)
              )
            }
            rating_row <- div(
              class = "rate-row",
              tags$span(class = "rate-label", "Was this helpful?"),
              rate_btn(2, "up",   "&#128077;", "Yes"),
              rate_btn(1, "okay", "&#128528;", "Okay"),
              rate_btn(0, "down", "&#128078;", "No")
            )
          } else {
            picked <- if (isTRUE(msg$rating >= 2)) "&#128077; Marked helpful"
                      else if (isTRUE(msg$rating == 1)) "&#128528; Marked okay"
                      else "&#128078; Marked not helpful"
            rating_row <- div(
              class = "rate-done",
              HTML(paste0(picked, " &middot; Thanks for the feedback"))
            )
          }
        }
        tagList(bubble, sources_row, rating_row)
      }
    })

    # No auto-scroll on send/answer/rating — the container keeps whatever
    # position the reader left it at. On the first render after a (re)load,
    # restore the scroll position saved for this tab (bottom if none saved).
    initial_scroll <- NULL
    if (!first_render_done && length(messages) > 0) {
      first_render_done <<- TRUE
      initial_scroll <- tags$script(HTML(
        "(function(){
           var c = document.getElementById('chat-container');
           if (!c) return;
           var v = null;
           try { v = sessionStorage.getItem('chatScrollTop'); } catch (e) {}
           c.scrollTop = (v !== null && !isNaN(+v)) ? +v : c.scrollHeight;
         })();"
      ))
    }

    tagList(do.call(tagList, message_elements), initial_scroll)
  })

  # Inline thumbs-up / thumbs-down under a bot reply. One shared input carries
  # the message index + rating (2 = up, 0 = down); feedback is optional.
  observeEvent(input$rate, {
    info <- input$rate
    if (is.null(info$idx)) return()
    i <- as.integer(info$idx)
    val <- as.integer(info$value)
    ch <- chatHistory()
    if (i < 1 || i > length(ch)) return()
    m <- ch[[i]]
    if (!isTRUE(m$rateable) || !is.null(m$rating)) return()

    ch[[i]]$rating <- val
    chatHistory(ch)

    q <- if (is.null(m$query)) "" else m$query
    u <- if (is.null(m$user_msg)) "" else m$user_msg
    tryCatch(
      py$save_feedback_to_duckdb(q, u, m$message, val),
      error = function(e) showNotification(
        paste("Could not save feedback:", conditionMessage(e)), type = "error"
      )
    )
  })
  
  # The textInput binding debounces by 250ms, so `input$userMessage` lags the
  # last few keystrokes. Read the live DOM value on send instead, or a fast
  # Enter / Send click drops the tail of the message.
  js <- "
    (function(){
      function fireSend(){
        var el = document.getElementById('userMessage');
        Shiny.setInputValue('sendNow',
          {text: el ? el.value : '', n: Math.random()}, {priority: 'event'});
      }
      $(document).on('keydown', '#userMessage', function(e){
        if (e.which === 13) { e.preventDefault(); fireSend(); }
      });
      $(document).on('click', '#sendMessage', function(){ fireSend(); });
    })();
"

  shinyjs::runjs(js)

  observeEvent(input$sendNow, {
    msg <- input$sendNow$text
    if (is.null(msg) || trimws(msg) == "") return()
    ch <- chatHistory()
    if (length(ch) > 0 && isTRUE(ch[[length(ch)]]$pending)) return()  # still busy
    sendMessage(msg)
  })

  sendMessage <- function(msg = NULL) {
    if (is.null(msg)) msg <- input$userMessage
    if (is.null(msg) || trimws(msg) == "") {
      return()
    }

    # Paint the user's bubble and the typing indicator immediately. The
    # blocking Python call is deferred to the next cycle (via shinyjs::delay)
    # so Shiny flushes this UI to the browser first instead of holding it
    # until query_qdrant() returns.
    current_chat <- chatHistory()
    current_chat[[length(current_chat) + 1]] <- list(sender = "user", message = msg)
    current_chat[[length(current_chat) + 1]] <- list(sender = "bot", pending = TRUE)
    chatHistory(current_chat)

    updateTextInput(session, "userMessage", value = "")
    shinyjs::disable("sendMessage")

    shinyjs::delay(50, {
      err_reply <- function(e) {
        list(NA, paste("Sorry, something went wrong:", conditionMessage(e)), list())
      }
      query_result <- tryCatch(py$query_qdrant(msg), error = err_reply)
      base_query(query_result[[1]])

      current_chat <- chatHistory()
      # Replace the trailing pending placeholder with the real reply.
      current_chat[[length(current_chat)]] <- list(
        sender = "bot",
        message = query_result[[2]],
        rateable = TRUE,
        query = base_query(),
        user_msg = msg,
        sources = if (length(query_result) >= 3) query_result[[3]] else list()
      )
      chatHistory(current_chat)

      shinyjs::enable("sendMessage")
    })
  }

}

options(shiny.host = "127.0.0.1", shiny.port = 5075)
shinyApp(ui = ui, server = server)
