require "csv"
require "json"

require_relative "lib/helpers"

class Converter
  def initialize
    @known_airports = {}
    @kb = KnowledgeBase.new()
  end

  def get_continent_from_tz(tz_string)
    a, b = tz_string.split("/")
    case a
    when "Europe"
      return "EU"
    when "America"
      if %w[Los_Angeles New_York].include?(b)
        return "NA"
      else
        return "SA"
      end
    when "Atlantic"
      if %w[Reykjavik].include?(b)
        return "EU"
      end

      return nil
    when "Asia"
      return "AS"
    when "Australia"
      return "OC"
    else
      raise StandardError, "Unknown continent for #{tz}"
    end
  end

  def get_airport(iata)
    d = @kb.get_airport_by_iata(iata)
    known = @known_airports[d['icao']]
    return known if known

    d = @kb.get_airport_by_iata(iata)
    airport = {
      "code" => d['icao'],
      "iata" => d['iata'],
      "lat" => d['lat'].to_f,
      "lon" => d['lon'].to_f,
      "tz" => d['tz'],
      "name" => d['name'],
      "type" => "medium_airport", # TODO
      "continent" => get_continent_from_tz(d['tz']),
      "country" => d['country'],
      "custom" => false
    }
    @known_airports[d['icao']] = airport
    return airport
  end

  def convert(source_csv, destination, user_id, username, display_name)
    raise StandardError, "Please provide an AirTrail user_id as 3rd argument" unless user_id
    raise StandardError, "Invalud user_id '#{user_id}'" unless user_id =~ /^[a-z0-9]{15}$/i

    res = {
      'users' => [
        {
          "id": user_id,
          "displayName": display_name,
          "username": username
        }

      ],
      'flights' => []
    }

    CSV.parse(File.read(source_csv), headers: true) do |row|
      time_departure = row["Gate Departure (Actual)"] || row['Gate Departure (Scheduled)']
      time_arrival = row["Gate Arrival (Actual)"] || row["Gate Arrival (Scheduled)"] || row["Landing (Actual)"] || row["Landing (Scheduled)"]
      cabin = row["Cabin Class"]
      if cabin == "PREMIUM_ECONOMY"
        cabin = "economy+"
      end
      aircraft = @kb.get_aircraft(row["Aircraft Type Name"])
      if aircraft
        aircraft = aircraft['Designator']
      end
      flight = {
        "date" => row["Date"],
        "from" => get_airport(row["From"]),
        "to" => get_airport(row["To"]),
        "departure" => @kb.conv_date(time_departure).strftime("%Y-%m-%dT%H:%M:%S.000+00:00"),
        "arrival" => @kb.conv_date(time_arrival).strftime("%Y-%m-%dT%H:%M:%S.000+00:00"),
        "duration" => @kb.flight_duration(time_departure, row["From"], time_arrival, row["To"]),
        "flightNumber" => row["Airline"] + row["Flight"],
        "flightReason" => row["Flight Reason"]&.downcase,
        "airline" => row["Airline"],
        "aircraft" => aircraft,
        "aircraftReg" => row["Tail Number"],
        "note" => row["Notes"],
        "seats" => [
          {
            "userId" => user_id,
            "guestName" => nil,
            "seat" => row["Seat Type"],
            "seatNumber" => row["Seat"],
            "seatClass" => cabin&.downcase
          }
        ]
      }
      res['flights'] << flight
    end

    out = File.new(destination, "w")
    out.write(JSON.pretty_generate(res))
    out.close
  end
end

c = Converter.new()

input_csv = ARGV[0]
output_json = ARGV[1]
ARGV.clear
puts "From your docker host, run: "
puts "
  docker exec --user root -it airtrail_db psql -U airtrail -d airtrail -c \"select id, username, display_name from public.user\"
"
puts ""
puts "Then please provide the following:"
print "\t user_id: "
user_id = gets.chomp
print "\t username: "
username = gets.chomp
print "\t display_name: "
display_name = gets.chomp
c.convert(input_csv, output_json, user_id, username, display_name)
