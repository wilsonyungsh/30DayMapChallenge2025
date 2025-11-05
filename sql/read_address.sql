create table overturemap_address as 
with base as(
SELECT
    id,
    unit,
    number,
    street,
    address_levels[1].value as state,
    address_levels[2].value as locality,
    st_x(geometry) as x,
    st_y(geometry) as y,
    sources[1].dataset as dataset,
    geometry AS geom
    --geometry as geom
    FROM read_parquet(
    's3://overturemaps-us-west-2/release/2025-10-22.0/theme=addresses/type=address/*',
    --filename=true,
    hive_partitioning=1
  ) 
  where country = 'AU' and address_levels[1].value = 'QLD') --AU QLD only
    select *,count(*) over (partition by locality) as suburb_address_cnt,-- calculate address count by suburb
    count(*) over (partition by unit,number,street,locality,state) as record_cnt -- calculate duplicate addresses
     from base 
