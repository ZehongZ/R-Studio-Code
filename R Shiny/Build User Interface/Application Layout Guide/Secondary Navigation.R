library(ggplot2)
library(shiny)

ui <- navbarPage(
  "My Application",
  tabPanel("Component 1"),
  tabPanel("Component 2"),
  navbarMenu("More",
             tabPanel("Sub-Component A"),
             tabPanel("Sub-Component B"))
)

server <- function(input, output, session) {
  
}

shinyApp(ui, server)