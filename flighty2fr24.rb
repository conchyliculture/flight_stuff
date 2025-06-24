# Converts Flighty dump into FlightRadar24
require "csv"
require "json"

require_relative "./lib/helpers"

def to_day(string)
  if string
    Time.parse(string).strftime("%H:%M:%S")
  else
    "00:00:00"
  end
end

class Converter
  def initialize
    @kb = KnowledgeBase.new()
  end

  def iata_to_full_airport(iata)
    a = @kb.airports.select { |a| a['iata'].downcase == iata.downcase }[0]
    return "#{a['name']} (#{a['iata']}/#{a['icao']})"
  end

  def icao_to_full_airline(airline)
    a = @kb.airlines.select { |a| (a['icao'] || '').downcase == airline.downcase }[0]
    if a['airline'] == "Peach Aviation"
      a['iata'] = 'MM'
    end
    return "#{a['airline']} (#{a['iata']}/#{a['icao']})"
  end

  def convert(source_csv, destination)
    fields_flightradar24 = ['Date', 'Flight number', 'From', 'To', 'Dep time', 'Arr time', 'Duration', 'Airline', 'Aircraft', 'Registration', 'Seat number', 'Seat type', 'Flight class', 'Flight reason', 'Note', 'Dep_id', 'Arr_id', 'Airline_id', 'Aircraft_id']

    CSV.open(destination, 'w', write_headers: true, headers: fields_flightradar24) do |csv_out|
      CSV.parse(File.read(source_csv), headers: true) do |row|
        time_departure = row["Gate Departure (Actual)"] || row['Gate Departure (Scheduled)']
        time_arrival = row["Gate Arrival (Actual)"] || row["Gate Arrival (Scheduled)"] || row["Landing (Actual)"] || row["Landing (Scheduled)"]
        duration_secs = @kb.flight_duration(time_departure, row["From"], time_arrival, row["To"])

        if duration_secs < 0
          duration_secs += duration_secs + 86_400
        end

        hours = duration_secs / 3600
        hours_s = format('%02d', hours)
        duration_secs %= 3600

        mins = duration_secs / 60
        mins_s = format('%02d', mins)
        duration_secs = format('%02d', duration_secs % 60)

        duration = "#{hours_s}:#{mins_s}:#{duration_secs}"
        csv_out << {
          "Date" => row["Date"],
          "Flight number" => row["Airline"] + row["Flight"],
          'From' => iata_to_full_airport(row["From"]),
          'To' => iata_to_full_airport(row["To"]),
          'Dep time' => to_day(time_departure),
          'Arr time' => to_day(time_arrival),
          'Duration' => duration,
          'Airline' => icao_to_full_airline(row["Airline"]),
          'Aircraft' => @kb.aircraft_fullname(row["Aircraft Type Name"]),
          'Registration' => row["Tail Number"],
          'Seat number' => row["Seat"],
          'Seat type' => row["Seat Type"],
          '"Flight class"' => seat_class(row["Cabin Class"]),
          '"Flight reason"' => reason(row["Flight Reason"]),
          'Note' => row["Notes"],
          'Dep_id' => "",
          'Arr_id' => "",
          'Airline_id' => "",
          'Aircraft_id' => ""
        }
      rescue StandardError => e
        pp row
        raise e
      end
    end
  end

  def reason(text)
    return {
      "LEISURE" => 1,
      "BUSINESS" => 2,
      "CREW" => 3
    }[text] || 4
  end

  def seat_class(text)
    return {
      "ECONOMY" => 0,
      "PREMIUM ECONOMY" => 3,
      "BUSINESS" => 1,
      "PRIVATE" => 2,
      "FIRST" => 4
    }[text]
  end
end

c = Converter.new()
c.convert(ARGV[0], ARGV[1])
