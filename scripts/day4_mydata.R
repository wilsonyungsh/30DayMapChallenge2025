pacman::p_load("tidyverse", "duckdb", "duckspatial", "sf", "mapgl", "mapdeck", "DBI", "strayr", "htmltools", "jsonlite")

mydata <- fromJSON("timeline_20251109.json")
semantic <- mydata$semanticSegments %>%
  mutate(sd = as_date(lubridate::ymd_hms(startTime), tz = "Australia/Brisbane")) %>%
  relocate(sd, .before = startTime)
## fishout only visit related information - test on one day
visit <- semantic %>%
  filter(lubridate::year(sd) == 2025) %>%
  select(sd, startTime, endTime, visit) %>% flatten() %>%
  separate(visit.topCandidate.placeLocation.latLng, into = c("lat", "lon"), sep = "°, ") %>%
  mutate(lon = str_remove_all(string = lon, pattern = "°"),
    duration = lubridate::ymd_hms(end, tz = "Australia/Brisbane") - starttiime) %>%
  filter(lat != "NA") %>%
  st_as_sf(coords = c("lon", "lat"), crs = 4326)

visit %>%
  mapdeck(style = mapdeck_style(style = "dark")) %>%
  add_scatterplot(radius = 100, fill_colour = "#ffffff")

setwd("data/")
con <- dbConnect(duckdb::duckdb(), dbdir = "google_timeline.duckdb", read_only = FALSE)
dbExecute(con, "install json")
dbExecute(con, "load json")
