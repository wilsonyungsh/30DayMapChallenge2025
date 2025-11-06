pacman::p_load("tidyverse", "duckdb", "duckspatial", "sf", "mapgl", "DBI", "strayr", "htmltools")

# connect to in memory duckdb
con <- dbConnect(duckdb::duckdb())

# create and load extension
dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
ddbs_install(con)
ddbs_load(con)

# check existing extension
dbGetQuery(con, "SELECT * FROM duckdb_extensions();")

# configure overturemap source aws info
dbExecute(con, "SET s3_region='us-west-2';")
dbExecute(con, "SET s3_endpoint='s3.us-west-2.amazonaws.com';")
dbExecute(con, "SET s3_use_ssl=true;")

# query to get aus address, details see read_address.sql, create a temp table called overturemap_address
dbExecute(con, read_file("sql/read_address.sql"))

## read in LGA boundary /suburb externally

seq_lgas <- read_absmap(name = "lga2022", remove_year_suffix = TRUE) %>%
  filter(lga_code %in% c(35010, 33430, 31000, 34590, 36250, 36720, 33960))
seq_suburbs <- read_absmap(name = "suburb2021", remove_year_suffix = TRUE) %>%
  filter(state_code == 3) %>% st_filter(seq_lgas) %>% select(suburb_name, areasqkm) %>%
  rename(suburb_areasqkm = areasqkm)

# write the table to duckdb as lga, suburb
ddbs_write_vector(con, seq_lgas, "lga")
ddbs_write_vector(con, seq_suburbs, "suburb", overwrite = TRUE)

# spatial join in duck db,overturemap_address and lga
ddbs_list_tables(con)
# create spatial index on both tables
dbExecute(con, "CREATE INDEX add_idx ON overturemap_address USING RTREE (geom);")
dbExecute(con, "CREATE INDEX lga_idx ON lga USING RTREE (geometry);")
dbExecute(con, "CREATE INDEX sub_idx ON suburb USING RTREE (geometry);")

# run spatial join in duckdb
dbExecute(con, read_file("sql/address_suburb_lga_join.sql"))


# read output as sf
address <- ddbs_read_vector(con, "addr_lga_sub", crs = 4326)
address_ipswich <- address %>% filter(lga_name == "Ipswich") %>%
  select(unit, number, street, suburb_name, state, lga_name, suburb_address_cnt, record_cnt, geom) %>%
  unite("address", unit, number, street, sep = " ", na.rm = TRUE) %>%
  mutate(tp = paste0("Address : ", address, "<br>Suburb : ", suburb_name, "<br>Suburb Address Count :", suburb_address_cnt))

## address point vis

breaks <- quantile(address_ipswich$suburb_address_cnt,
  probs = seq(0, 1, length.out = 10),
  na.rm = TRUE) %>% unname()
colour_value <- RColorBrewer::brewer.pal(name = "RdYlGn", n = length(breaks)) %>% rev()

maplibre(center = c(152.76223617980878, -27.612925002928428), zoom = 15,
  carto_style(style_name = "dark-matter")) %>%
  add_circle_layer(id = "address", source = address_ipswich,
    circle_color  = interpolate("suburb_address_cnt",
      type = "linear",
      values = breaks,
      stops = colour_value), tooltip = "tp",
    circle_radius = 5, circle_opacity = 0.3, min_zoom = 12) %>%
  add_continuous_legend(legend_title = "suburb address record count",
    values = c("Low", "Medium(3K)", "High(12K)"),
    colors = colour_value, position = "bottom-left") %>%
  add_control(
    html = "<div style='position:relative;top:10px;left:50%;transform:translateX(-50%);
                     background-color: rgba(255,255,255,0.8); padding:8px 15px; border-radius:5px;
                     font-family:Arial, sans-serif; font-weight:bold;font-size:20px;'>Ipswich Address count by suburb</div>",
    position = "top-left"
  ) %>%
  add_control(
    html = "<div style='position:relative;
                     background-color: rgba(255,255,255,0.6); padding:4px 8px; border-radius:3px;
                     font-family:Arial, sans-serif; font-size:0.8em;'>Data Source: Overture Maps Foundation</div>",
    position = "bottom-right"
  )
