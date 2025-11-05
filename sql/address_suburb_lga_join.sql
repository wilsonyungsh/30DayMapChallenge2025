--with base as(
--select a.*,b.lga_name from overturemap_address a 
--join lga b on st_within(a.geom,b.geometry) where st_within(a.geom,b.geometry)
--)
--select base.*,c.suburb_name,c.suburb_areasqkm from base 
--join suburb c on st_within(base.geom,c.geometry) where st_within(base.geom,c.geometry)

create table add_lga as
select a.*,b.lga_name from overturemap_address a 
join lga b on st_intersects(a.geom,b.geometry) where st_within(a.geom,b.geometry) ;

CREATE INDEX idx_add_lga ON add_lga USING RTREE (geom) ; 
create table addr_lga_sub as 
select add_lga.*,c.suburb_name,c.suburb_areasqkm from add_lga 
join suburb c on st_intersects(add_lga.geom,c.geometry) where st_within(add_lga.geom,c.geometry)