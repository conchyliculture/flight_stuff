# Flight Stuff

Collection of helpful scripts for flight logging stuff.

## flighty2fr24.rb

Converts data exported from [Flighty](https://flighty.com/) into a FlightRadar24 format.

```bash
$ ruby flighty2fr24.rb /tmp/FlightyExport-2025-06-17.csv /tmp/fr24.csv
```

Then `/tmp/fr24.csv` can be either imported into flightradar24.com, or [AirTrail](https://airtrail.johan.ohly.dk/).

## flighty2airtrail.rb

Converts data exported from [Flighty](https://flighty.com/) into AirTrail JSON format.

```bash
$ ruby flighty2airtrail.rb /tmp/FlightyExport-2025-06-17.csv /tmp/airtrail.json

From your docker host, run: 

  docker exec --user root -it airtrail_db psql -U airtrail -d airtrail -c "select id, username, display_name from public.user"

Then please provide the following:
         user_id: hvdhwqsfdqdsf
         username: test
         display_name: test
```

The script requires some information from your current install of airtrail. It will only work for a single user.


Then `/tmp/airtrail.json` can be imported into [AirTrail](https://airtrail.johan.ohly.dk/).


## Some AirTrail tips & tricks

Add TXL back to airports (rip):

```bash
docker exec --user root -it airtrail_db psql -U airtrail -d airtrail -c "INSERT INTO airport VALUES ('EDDT', 'TXL', 52.55925537956253, 13.290615673504504, 'Europe/Berlin', 'Berlin TXL', 'large_airport', 'EU', 'DE', 't');
```