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
        bubble <- div(
          class = if (isTRUE(msg$rateable)) "d-flex justify-content-start mb-1"
                  else "d-flex justify-content-start mb-2",
          div(class = "rounded px-3 py-2",
              style = "background-color: #3a76d8; color: white; max-width: 75%;",
              p(msg$message))
        )

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
        tagList(bubble, rating_row)
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
  
  observeEvent(input$sendMessage, {
    sendMessage()
  })
  
  js <- "
    $(document).on('keypress', '#userMessage', function(e) {
      if(e.which === 13) {
        Shiny.setInputValue('enterPressed', true, {priority: 'event'});
        e.preventDefault();
     }
    });
"
  
  shinyjs::runjs(js)
  
  observeEvent(input$enterPressed, {
    if (!is.null(input$userMessage) && trimws(input$userMessage) != "") {
      sendMessage()
    }
  })

  sendMessage <- function() {
    msg <- input$userMessage
    if (trimws(msg) == "") {
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
      query_result <- tryCatch(
        py$query_qdrant(msg),
        error = function(e) list(NA, paste("Sorry, something went wrong:", conditionMessage(e)))
      )
      base_query(query_result[[1]])

      current_chat <- chatHistory()
      # Replace the trailing pending placeholder with the real reply.
      current_chat[[length(current_chat)]] <- list(
        sender = "bot",
        message = query_result[[2]],
        rateable = TRUE,
        query = base_query(),
        user_msg = msg
      )
      chatHistory(current_chat)

      shinyjs::enable("sendMessage")
    })
  }

}

options(shiny.host = "127.0.0.1", shiny.port = 5075)
shinyApp(ui = ui, server = server)