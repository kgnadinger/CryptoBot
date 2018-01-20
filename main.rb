require './bot'
require './ven_eth'
require 'sequel'

bot = BinanceBot.new

# Returns a hash 
	# - open_time
	# - close_price
	# - close_time
raw_price_history = bot.price_history("VENETH", '5m', 500)
db = Sequel.connect(adapter: 'mysql2', user: Secrets.database_username, 
							 password: Secrets.database_password, database: 'binance')
raw_price_history.each do |raw_price|
	v = VenEth.new(opening_time: raw_price[:open_time], closing_price: raw_price[:close_price], closing_time: raw_price[:close_time], database: db)
	v.create!
end



# price_history = raw_price_history.map { |p| p[:close_price] }


# data = Indicators::Data.new(price_history)

# rsi = data.calc(:type => :rsi, :params => 14).output
# macdArray = data.calc(:type => :macd, :params => [12, 26, 9]).output


# macdArray.each_with_index do |macd, index|
# 	if macd && index > 26
# 		firstMacd = macdArray[index - 1][0] * 1000
# 		nextMacd = macd[0] * 1000
# 		# puts "#{firstMacd} #{nextMacd}"
# 		if ((firstMacd / nextMacd) < 0) && bot.rsi_recently_crossed_threshold(rsi, index)
# 			puts "MACD: [#{macdArray[index - 1][0]}, #{macd[0]}], Price: #{price_history[index]}, RSI: #{rsi[index]}}"
# 		end
# 	end
# end