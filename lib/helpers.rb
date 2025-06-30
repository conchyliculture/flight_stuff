class TimeWithTZ < Time
  require "tzinfo"
  def self.find_timezone(zone)
    TZInfo::Timezone.get(zone)
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

class KnowledgeBase
  attr_accessor :airports, :airlines, :aircrafts

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

  def get_airport_by_iata(iata)
    found = @airports.select { |airport| airport['iata'] == iata }
    case found.size
    when 1
      return found[0]
    when 0
      raise StandardError, "Unable to find airport for IATA code #{iata}"
    else
      raise StandardError, "Found too many (#{found.size} airports matching IATA code #{iata}"
    end
  end

  def aircraft_fullname(aircraft)
    avion = get_aircraft(aircraft)
    if avion
      return "#{avion['ManufacturerCode'].downcase.capitalize} #{avion['ModelFullName']} (#{avion['Designator']})"
    end

    return aircraft
  end

  def get_aircraft(aircraft_string)
    return nil unless aircraft_string

    avion = nil
    aircraft = aircraft_string.strip()
    case aircraft
    when "Fairchild Merlin/Metro/Expediter"
      return {"ModelFullName" => aircraft}
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
    return avion
  end

  def airport_tz(code)
    airport = @airports.select { |a| a['iata'].downcase == code.downcase or a['icao'].downcase == code.downcase }
    raise StandardError, "Airport not found: #{code}" unless airport or airport.empty?
    raise StandardError, "Found too many airports for: #{code}" if airport.size > 1

    return airport[0]["tz"]
  end

  def conv_date(string, airport = nil)
    if string =~ /^....-..-..T..:..$/
      string = "#{string}:00"
    end
    if airport
      string = "#{string} #{airport_tz(airport)}"
    end
    return TimeWithTZ.new(string)
  end

  def flight_duration(from_date, from_airport, to_date, to_airport)
    unless from_date and to_date
      raise StandardError, "can't calc duration for #{from_date} #{from_airport} #{to_date} #{to_airport}"
    end

    dt_departure = conv_date(from_date, from_airport).to_i
    dt_arrival = conv_date(to_date, to_airport).to_i

    sec = dt_arrival - dt_departure
    return sec
  end

  def get_airline(code)
    res = nil
    if code.size == 2
      res = @airlines.select{|airline| airline['iata'] == code }
    elsif code.size == 3
      res = @airlines.select{|airline| airline['icao'] == code }
    else
      raise StandardError, "Illegal airline code : #{code}"
    end

    case res.size
    when 1
      return res[0]
    when 0
      raise StandardError, "Could not find airline with code #{code}"
    else
      raise StandardError, "Found too many airlines matching code #{code}"
    end
  end
end
