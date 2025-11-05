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

# use duckspatial to load the table as sf in R
qld_address <- ddbs_read_vector(con, "overturemap_address", crs = 4326)

## test viz

maplibre(bounds = qld_address %>% head(1000)) %>%
  add_circle_layer(id = "add", source = qld_address %>% head(1000), circle_color = "blue")

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

# calculate suburb/lga address density
address_density_suburb <- dbGetQuery(con, "select suburb_name,suburb_areasqkm,count(*) as address_cnt,round(count(*)/suburb_areasqkm) as address_density_sqkm from addr_lga_sub group by suburb_name,suburb_areasqkm") %>%
  left_join(seq_suburbs %>% select(-suburb_areasqkm), by = "suburb_name") %>% st_as_sf()
# read output as sf
address_final <- ddbs_read_vector(con, "addr_lga_sub", crs = 4326)
add <- address_final %>% filter(lga_name %in% c("Gold Coast"))

## address point vis
maplibre(bounds = add) %>%
  add_circle_layer(id = "address", source = add,
    circle_color  = match_expr("lga_name", values = add$lga_name %>% unique(),
      stops = RColorBrewer::brewer.pal(name = "Set1", n = 3)),
    # interpolate("suburb_address_cnt",
    # type = "linear",
    # values = pretty(c(0, 37000), 10),
    # stops = hcl.colors(palette = "viridis", n = 9)),
    circle_radius = 5, circle_opacity = 0.5,
    circle_translate = c(0, -20)) %>%
  add_categorical_legend(legend_title = "LGA",
    values = add$lga_name %>% unique(),
    colors = RColorBrewer::brewer.pal(name = "Set1", n = 3))


## address density viz
breaks <- quantile(address_density_suburb$address_density_sqkm,
  probs = seq(0, 1, length.out = 7),
  na.rm = TRUE) %>% unname()
maplibre(bounds = address_density_suburb) %>%
  add_fill_layer(id = "density", source = address_density_suburb %>% mutate(tp = paste0("Suburb : ", suburb_name, "<br>Density per sqkm: ", scales::comma(address_density_sqkm))),
    fill_color = interpolate("address_density_sqkm",
      type = "linear",
      values = breaks,
      stops = hcl.colors(palette = "viridis", n = length(breaks))),
    fill_opacity  = 0.5, tooltip = "tp") %>%
  add_continuous_legend(legend_title = "Address Density per sqkm suburb", position = "bottom-left",
    values = format(breaks[c(1, 4, 5, 7)], big.mark = ","),
    colors = hcl.colors(palette = "viridis", n = length(breaks))) %>%
  add_control(
    html = "<div style='position:relative;top:10px;left:50%;transform:translateX(-50%);
                     background-color: rgba(255,255,255,0.8); padding:8px 15px; border-radius:5px;
                     font-family:Arial, sans-serif; font-weight:bold;font-size:20px;'>South East Queensland Address Density Map</div>",
    position = "top-left"
  ) %>%
  # 資料來源
  add_control(
    html = "<div style='position:relative;bottom:10px;right:10px;
                     background-color: rgba(255,255,255,0.6); padding:4px 8px; border-radius:3px;
                     font-family:Arial, sans-serif; font-size:0.8em;'>Data Source: Overture Maps Foundation</div>",
    position = "bottom-right"
  )
