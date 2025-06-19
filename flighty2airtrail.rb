# Converts Flighty dump into FlightRadar24
require "csv"
require "json"

class TimeWithTZ < Time
  require "tzinfo"
  def self.find_timezone(zone)
    TZInfo::Timezone.get(zone)
  end
end

def to_day(string)
  if string
    Time.parse(string).strftime("%H:%M:%S")
  else
    "00:00:00"
  end
end

def pull_airline_codes(dest)
  require "net/http"
  require "nokogiri"
  bad_airlines = ['deutsche luft hansa']
  known_icaos = []

  CSV.open(dest, 'w', write_headers: true, headers: %w[iata icao airline]) do |csv_out|
    r = Nokogiri::HTML.parse(Net::HTTP.get(URI.parse("https://en.wikipedia.org/wiki/List_of_airline_codes")))
    r.css("table.wikitable tbody tr")[1..-1].each do |row|
      iata, icao, airline = row.css('td')[0..2].map { |e| e.text.strip() }
      next if bad_airlines.include?(airline.downcase())

      next if known_icaos.include?(icao)

      known_icaos << icao
      csv_out << { 'iata' => iata, 'icao' => icao, 'airline' => airline }
    end
  end
end

def pull_airports(dest)
  File.new(dest, 'w').write(Net::HTTP.get(URI.parse("https://github.com/mborsetti/airportsdata/raw/refs/heads/main/airportsdata/airports.csv")))
end

def pull_aircrafts(dest)
  resp = Net::HTTP.post(URI.parse("https://www4.icao.int/doc8643/External/AircraftTypes"), nil, { 'Accept' => "application/json, text/javascript, */*; q=0.01" })
  File.new(dest, "w").write(resp.body)
end

class Converter
  def initialize
    unless File.exist?("data/airports.csv")
      pull_airports("data/airports.csv")
    end
    @airports = CSV.parse(File.read("data/airports.csv"), headers: true).reject { |a| a['iata'] == "" }
    unless File.exist?("data/airline_codes.csv")
      pull_airports("data/airline_codes.csv")
    end
    @airlines = CSV.parse(File.read("data/airline_codes.csv"), headers: true)

    unless File.exist?("data/aircrafts.json")
      pull_aircrafts("data/aircrafts.json")
    end
    @aircrafts = JSON.parse(File.read("data/aircrafts.json"))
  end

  def iata_to_full_airport(iata)
    a = @airports.select { |a| a['iata'].downcase == iata.downcase }[0]
    return "#{a['name']} (#{a['iata']}/#{a['icao']})"
  end

  def icao_to_full_airline(airline)
    a = @airlines.select { |a| (a['icao'] || '').downcase == airline.downcase }[0]
    return "#{a['airline']} (#{a['iata']}/#{a['icao']})"
  end

  def aircraft_fullname(aircraft)
    return nil unless aircraft

    avion = nil
    aircraft = aircraft.strip()
    case aircraft
    when "Fairchild Merlin/Metro/Expediter"
      return aircraft
    when /Airbus A/
      avion = @aircrafts.select { |a| a["ModelFullName"].start_with?(aircraft.gsub("Airbus A", "A-")) }[0]
    when /Boeing 737 MAX/
      avion = @aircrafts.select { |a| a["ModelFullName"] == aircraft.gsub("Boeing ", "") }[0]
    when /Boeing/
      avion = @aircrafts.select { |a| a["ModelFullName"].start_with?(aircraft.gsub("Boeing ", "").gsub(" ", "").gsub("900ER", "900")) }[0]
    when /Fokker/
      avion = @aircrafts.select { |a| a["Designator"] == aircraft.gsub("Fokker ", "F") }[0]
    when "Embraer 195 E2"
      avion = @aircrafts.select { |a| a["Designator"] == "E295" }[0]
    when /Embraer 175/
      avion = @aircrafts.select { |a| a["Designator"] == "E75L" }[0]
    when /Embraer/
      avion = @aircrafts.select { |a| a["Designator"].start_with?(aircraft.gsub("Embraer ", "E").gsub(" ", "-")) }[0]
    when /CRJ.00/
      avion = @aircrafts.select { |a| a["ModelFullName"].end_with?(aircraft.gsub("Bombardier ", "").gsub("CRJ", "CRJ-")) }[0]
    end
    if avion
      return "#{avion['ManufacturerCode'].downcase.capitalize} #{avion['ModelFullName']} (#{avion['Designator']})"
    end

    return aircraft
  end

  def convert(source_csv, destination)
    fields_flightradar24 = ['Date', 'Flight number', 'From', 'To', 'Dep time', 'Arr time', 'Duration', 'Airline', 'Aircraft', 'Registration', 'Seat number', 'Seat type', 'Flight class', 'Flight reason', 'Note', 'Dep_id', 'Arr_id', 'Airline_id', 'Aircraft_id']

    CSV.open(destination, 'w', write_headers: true, headers: fields_flightradar24) do |csv_out|
      CSV.parse(File.read(source_csv), headers: true) do |row|
        begin
          time_departure = row["Gate Departure (Actual)"] || row['Gate Departure (Scheduled)']
          time_arrival = row["Gate Arrival (Actual)"] || row["Gate Arrival (Scheduled)"] || row["Landing (Actual)"] || row["Landing (Scheduled)"]
          csv_out << {
            "Date" => row["Date"],
            "Flight number" => row["Airline"] + row["Flight"],
            'From' => iata_to_full_airport(row["From"]),
            'To' => iata_to_full_airport(row["To"]),
            'Dep time' => to_day(time_departure),
            'Arr time' => to_day(time_arrival),
            'Duration' => flight_duration(time_departure, row["From"], time_arrival, row["To"]),
            'Airline' => icao_to_full_airline(row["Airline"]),
            'Aircraft' => aircraft_fullname(row["Aircraft Type Name"]),
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

  def airport_tz(code)
    airport = @airports.select { |a| a['iata'].downcase == code.downcase or a['icao'].downcase == code.downcase }
    raise StandardError, "Airport not found: #{code}" unless airport or airport.empty?
    raise StandardError, "Found too many airports for: #{code}" if airport.size > 1

    return airport[0]["tz"]
  end

  def flight_duration(from_date, from_airport, to_date, to_airport)
    unless from_date and to_date
      raise StandardError, "can't calc duration for #{from_date} #{from_airport} #{to_date} #{to_airport}"
    end

    if to_date =~ /^....-..-..T..:..$/
      to_date = "#{to_date}:00"
    end
    if from_date =~ /^....-..-..T..:..$/
      from_date = "#{from_date}:00"
    end

    dt_arrival = TimeWithTZ.new("#{to_date} #{airport_tz(to_airport)}").to_i
    dt_departure = TimeWithTZ.new("#{from_date} #{airport_tz(from_airport)}").to_i

    sec = dt_arrival - dt_departure
    if sec < 0
      sec += sec + 86_400
    end

    hours = sec / 3600
    hours_s = format('%02d', hours)
    sec %= 3600

    mins = sec / 60
    mins_s = format('%02d', mins)
    sec = format('%02d', sec % 60)

    return "#{hours_s}:#{mins_s}:#{sec}"
  end
end

c = Converter.new()
c.convert(ARGV[0], ARGV[1])
