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

ui <- page_sidebar(
  
  theme = custom_theme,
  
  sidebar = sidebar(
    width = 300,
    title = "Settings",
    
    card(
      card_header("Chatbot Info", style = "background-color: #004aab; color: white;"),
      p("This chatbot connects with knowledge base documents vectorized and stored in Weaviate."), 
      p("Ask all knowledge base related questions here!")
    ),
    
    hr(),
    
    card(
      card_header("Options", style = "background-color: #004aab; color: white;"),
      shinyWidgets::switchInput("darkMode", "Dark Mode", value = FALSE, 
                               onLabel = "ON", offLabel = "OFF",
                               onStatus = "#1d6522", offStatus = "#3a76d8")
    )
  ),
  
  card(
    card_header("Chat Window", style = "background-color: #004aab; color: white;"),
    div(
      id = "chat-container",
      style = "height: 400px; overflow-y: auto; padding: 15px; 
                margin-bottom: 15px; border: 1px solid #F8B092; 
                border-radius: 5px;",
      uiOutput("chatMessages")
    ),
    card_footer(
      div(
        class = "d-flex",
        textInput("userMessage", "Type a message", placeholder = "Type your message here...", 
                    width = "100%"),
        actionButton("sendMessage", "Send", class = "btn ml-2",
                     style = "background-color: #F16125; color: white;")
      )
    ),
    
    # Feedback UI (Initially Hidden)
    div(
      id = "feedback-section",
      style = "display: none; margin-top: 15px;",
      h4("Rate the last response:", style = "color: #004aab;"),
      radioButtons("feedback", "", choices = list("👍 Good" = 2, 
                                                      "Okay" = 1, "👎 Bad" = 0), inline = TRUE),
      actionButton("submitFeedback", "Submit Feedback", class = "btn",
                   style = "background-color: #1d6522; color: white;"),
      hr()
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
      /* Custom styling for the cards */
      .card { border-color: #3a76d8 !important; }
    "))
  ),
  ui
)

server <- function(input, output, session) {

  chatHistory <- reactiveVal(list(list(sender = "bot", 
                  message = "Hello! I'm your chatbot assistant. How can I help you today?")))
  
  feedbackNeeded <- reactiveVal(FALSE)  # Initially, feedback is not needed
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

  observe({
    if (input$darkMode) {
      session$setCurrentTheme(dark_theme)
    } else {
      session$setCurrentTheme(light_theme)
    }
  })

  shinyjs::hide("feedback-section")
        
  output$chatMessages <- renderUI({
    messages <- chatHistory()
    message_elements <- lapply(messages, function(msg) {
      if (msg$sender == "user") {
        div(
          class = "d-flex justify-content-end mb-2",
          div(class = "rounded px-3 py-2", 
              style = "background-color: #F8B092; color: black; max-width: 75%;", 
              p(msg$message))
        )
      } else {
        div(
          class = "d-flex justify-content-start mb-2",
          div(class = "rounded px-3 py-2", 
              style = "background-color: #3a76d8; color: white; max-width: 75%;", 
              p(msg$message))
        )
      }
    })
    do.call(tagList, message_elements)
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
    # Prevent new message if feedback is not provided
    if (feedbackNeeded()) {
        showNotification("Please submit feedback before asking another question.", type = "warning")
        return()
    }

    msg <- input$userMessage
    if (trimws(msg) == "") {
      return()
    }
    
    current_chat <- chatHistory()
    current_chat[[length(current_chat) + 1]] <- list(sender = "user", message = msg)
    chatHistory(current_chat)
    
    query_result <- py$query_weaviate(msg)

    base_query(query_result[[1]])
    bot_response <- query_result[[2]]
    
    shinyjs::delay(500, {
      current_chat <- chatHistory()
      current_chat[[length(current_chat) + 1]] <- list(sender = "bot", message = bot_response)
      chatHistory(current_chat)
      
      runjs("document.getElementById('chat-container').scrollTop = document.getElementById('chat-container').scrollHeight;")
      shinyjs::show("feedback-section")
      feedbackNeeded(TRUE) 
    })
    
    updateTextInput(session, "userMessage", value = "")
  }

    # Handle feedback submission
    observeEvent(input$submitFeedback, {

        # Prevent missing feedback submission
        if (is.null(input$feedback)) {
          showNotification("Please provide feedback before submitting.", type = "warning")
          return()
        }
      
        last_chat_bot <- tail(chatHistory(), 1)[[1]]
        last_chat_user <- tail(chatHistory(), 2)[[1]]

        py$save_feedback_to_duckdb(base_query(), last_chat_user$message, last_chat_bot$message, as.integer(input$feedback))
        showNotification("Feedback submitted! Thank you!", type = "message")
        
        # Hide feedback UI after submission
        shinyjs::hide("feedback-section")
        feedbackNeeded(FALSE) 

        # Reset feedback input
        updateRadioButtons(session, "feedback", selected = character(0))
    })

}

options(shiny.host = "0.0.0.0", shiny.port = 5075)
shinyApp(ui = ui, server = server)