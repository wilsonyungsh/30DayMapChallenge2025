pacman::p_load("tidyverse", "sf", "mapdeck", "jsonlite")

# get from device on goolge timeline output
mydata <- fromJSON("timeline_20251109.json")

# get semantic data only, covert time to timestamp
semantic <- mydata$semanticSegments %>%
  mutate(sd = as_date(lubridate::ymd_hms(startTime), tz = "Australia/Brisbane"),
    across(c(startTime, endTime), .fns = ~ ymd_hms(.x, tz = "Australia/Brisbane")))

## flatten semantic
visit <- semantic %>%
  select(sd, startTime, endTime, visit) %>% flatten() %>%
  separate(visit.topCandidate.placeLocation.latLng, into = c("lat", "lon"), sep = "°, ") %>%
  filter(lat != "NA") %>%
  mutate(lon = str_remove_all(string = lon, pattern = "°"),
    place_type = if_else(visit.topCandidate.semanticType %in% c("INFERRED_WORK", "INFERRED_HOME", "WORK", "HOME"), "Home&Work", "Non_Home&Work"),
    duration = round(as.numeric(endTime - startTime) / 60, 2)) %>%
  st_as_sf(coords = c("lon", "lat"), crs = 4326, remove = FALSE)

my_data_non_homework <-
  visit %>% select(startTime, endTime, place_type, duration, lon, lat, geometry) %>%
  filter(place_type == "Non_Home&Work") %>%
  mutate(across(c(lon, lat), ~ as.numeric(.x)))

my_stats <-
  my_data_non_homework %>% st_drop_geometry() %>% mutate(date = as.Date(startTime)) %>%
  unite("loc", c(lon, lat), sep = "|") %>%
  group_by(date) %>% summarise(loc_cnt = n_distinct(loc), hours_outside_hw = sum(duration)) %>% arrange(desc(loc_cnt))

my_data_non_homework %>%
  mapdeck(location = c(151.08985100485512, -33.82095296781856), zoom = 9, pitch = 45) %>%
  add_hexagon(color = "duration", color_function = "sum", radius = 500, color_opacity = 0.1, fill_opacity = 0.1,
    elevation_scale = 20, update_view = FALSE) %>%
  add_title("My footprint 2013-2025 from google timeline data")
