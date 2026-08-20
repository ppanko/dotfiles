view_df <- function(x,
                    name = deparse(substitute(x)),
                    file = "dt_viewer.html") {
  widget <- DT::datatable(
    x,
    options = list(autoWidth = TRUE),
    filter  = list(position = "top", clear = FALSE)
  )

  htmlwidgets::saveWidget(
    widget,
    file,
    selfcontained = FALSE,
    libdir        = paste0(tools::file_path_sans_ext(file), "_files"),
    title         = paste("DT:", name)
  )

  browseURL(normalizePath(file))
}
