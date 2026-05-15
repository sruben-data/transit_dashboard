/*
This script creates the transit_dashboard database in PostgreSQL, containing 8 tables in total:
    1 Fact table - trips
    7 Dimension tables - riders, drivers, vehicles, shifts, zone, date, time of day

*/

/* Interactive psql setup commands
psql --help
createdb --help
dropdb --help

-- Create the database in interactive psql session
psql -U postgres -c 'CREATE DATABASE transit_ops;' *semi-colon is statement terminator
OR
1. psql -U postgres
2. CREATE DATABASE transit_ops;
3. \q

-- Load tables and data
psql -U postgres -d transit_ops -f 'C:\full_file_path' *This is a placeholder path
OR
1. psql -U postgres
2. \i 'C:\full_file_path'

full path = 'C:\Users\samue\code\Projects\transit_dashboard\transit_db.sql'
*/

-- Create dimension tables (in order of foreign key dependencies)
CREATE TABLE dim_riders (
    rider_id INTEGER PRIMARY KEY,
    rider_type VARCHAR(20) NOT NULL DEFAULT 'general',
    occupancy_units INTEGER GENERATED ALWAYS AS(
        CASE
            WHEN rider_type = 'general' THEN 1
            ELSE 2 -- paratransit riders take up two seats (one row)
        END
    ),

    CONSTRAINT valid_rider_type CHECK(rider_type IN('general', 'paratransit'))
);

CREATE TABLE dim_drivers (
    driver_id INTEGER PRIMARY KEY,
    driver_name VARCHAR(100) NOT NULL
);

CREATE TABLE dim_vehicles (
    vehicle_id INTEGER PRIMARY KEY,
    vehicle_type VARCHAR(50) NOT NULL DEFAULT 'VAN',
    vehicle_occupancy INTEGER NOT NULL DEFAULT 10,

    CONSTRAINT valid_vehicle_type CHECK(vehicle_type IN('VAN', 'CUT','WAV')),
    CONSTRAINT valid_occupancy CHECK(
        (vehicle_type IN('VAN','WAV') AND vehicle_occupancy = 10) OR
        (vehicle_type = 'CUT' AND vehicle_occupancy = 15)
    )
);

CREATE TABLE dim_shifts (
    shift_id INTEGER PRIMARY KEY,
    driver_id INTEGER NOT NULL, --FK
    vehicle_id INTEGER NOT NULL, --FK
    shift_start TIME NOT NULL,
    shift_end TIME NOT NULL,
    shift_date DATE NOT NULL,

    CONSTRAINT FK_driver_shifts FOREIGN KEY (driver_id)
    REFERENCES dim_drivers(driver_id),
    CONSTRAINT FK_vehicle_shifts FOREIGN KEY (vehicle_id)
    REFERENCES dim_vehicles(vehicle_id)
);

CREATE TABLE dim_zone (
    zone_key INTEGER NOT NULL,
    zone_id INTEGER PRIMARY KEY,
    zone_name VARCHAR(50) NOT NULL,
    service_date_start DATE NOT NULL,
    service_date_end DATE NOT NULL,
    service_hours_start TIME NOT NULL,
    service_hours_end TIME NOT NULL,
    max_walk_distance INTEGER NOT NULL,
    zone_dimensions POLYGON NOT NULL
);

/*
    Ideally, this table is auto-populated each time a trip is created/inserted, with a single entry
    per unique trip date & day of week.
*/
CREATE TABLE dim_date (
    trip_date DATE,
    day_of_week VARCHAR(10) NOT NULL,
    is_weekday BOOLEAN NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    PRIMARY KEY (trip_date, day_of_week), -- Composite Primary Key

    CONSTRAINT valid_day_of_week CHECK(
        day_of_week IN('Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'))
);

CREATE TABLE dim_time_of_day (
    hour_of_day INTEGER PRIMARY KEY,
    hour_bucket VARCHAR(10) NOT NULL, -- To group hours into buckets like Peak, Off-Peak, etc
    is_peak_hour BOOLEAN NOT NULL, -- This will become problematic if there are multiple zones with different peak hours
    is_service_hour BOOLEAN NOT NULL, -- This will become problematic if there are multiple zones with different service hours
    period_name VARCHAR(20), -- Double-check purpose of this column

    CONSTRAINT valid_hour_of_day CHECK(
        hour_of_day BETWEEN 0 AND 23
    )
);

-- Create trips fact table
CREATE TABLE fact_trips (
    trip_id INTEGER PRIMARY KEY,
    rider_id INTEGER NOT NULL, --FK
    driver_id INTEGER NOT NULL, --FK
    vehicle_id INTEGER NOT NULL, --FK
    shift_id INTEGER NOT NULL, --FK
    trip_date DATE NOT NULL,
    hour_of_day INTEGER NOT NULL, -- Ideally auto-populated from pickup_ts
    request_ts TIMESTAMP NOT NULL,
    quoted_pickup_ts TIMESTAMP NOT NULL,
    actual_pickup_ts TIMESTAMP NOT NULL,
    quoted_dropoff_ts TIMESTAMP NOT NULL,
    actual_dropoff_ts TIMESTAMP NOT NULL,
    trip_status VARCHAR(20) NOT NULL,
    -- request lat, lon defines which zone this trip takes place in
    request_lat DECIMAL(8,6) NOT NULL, 
    request_lon DECIMAL(9,6) NOT NULL,
    pickup_lat DECIMAL(8,6) NOT NULL, 
    pickup_lon DECIMAL(9,6) NOT NULL,
    dropoff_lat DECIMAL(8,6) NOT NULL, 
    dropoff_lon DECIMAL(9,6) NOT NULL,

    CONSTRAINT FK_rider_trips FOREIGN KEY (rider_id)
    REFERENCES dim_riders(rider_id),
    CONSTRAINT FK_driver_trips FOREIGN KEY (driver_id)
    REFERENCES dim_drivers(driver_id),
    CONSTRAINT FK_vehicle_trips FOREIGN KEY (vehicle_id)
    REFERENCES dim_vehicles(vehicle_id),
    CONSTRAINT FK_shift_trips FOREIGN KEY (shift_id)
    REFERENCES dim_shifts(shift_id),

    CONSTRAINT valid_trip_status CHECK(
        trip_status IN('COMPLETED', 'NO_SHOW', 'CANCELLED_RIDER', 'CANCELLED_DRIVER')
    )

);

-- NOT NULL
-- DEFAULT CURRENT_TIMESTAMP
/*
foreign key definition: https://www.postgresql.org/docs/current/sql-createtable.html
CONSTRAINT constraint_name
FOREIGN KEY (fk_name)
REFERENCES table(pk_name)
*/

/*
data validation - CHECK constraint
    CONSTRAINT chk_some_column_values CHECK (some_column IN ('Yes', 'No'))
*/

/*
Notes
1. How would I cap out a vehicle's WAV occupancy vs total?
Ex - once it has 2 wheelchair users, cannot accommodate more, though it can have 6 regular riders (3 rows)
*/