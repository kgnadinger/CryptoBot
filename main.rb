require './bot'
Dir["./models/*.rb"].each {|file| require file }
require 'sequel'
require './back_tester'

bot = BinanceBot.new
# info = bot.account_info
# eth_hash = {}
# bot.account_info["balances"].each do |b|
# 	if b["asset"] == "ETH"
# 		eth_hash = b
# 	end
# end
# puts eth_hash

# create_test_order(symbol, side, type="MARKET", quantity)

bot.stream

# Returns a hash 
	# - open_time
	# - close_price
	# - close_time
# earliest_time = EthUsdt.order(:opening_time).first.opening_time
# raw_price_history = bot.price_history_with_end_time("ETHUSDT", '5m', 500, earliest_time)

# raw_price_history.each do |raw_price|
# 	ven_eth = VenEth.where(opening_time: raw_price[:open_time])
# 	if ven_eth && ven_eth.first
# 		ven_eth.first.update(opening_time: raw_price[:open_time], 
# 							 closing_price: raw_price[:close_price], 
# 							 closing_time: raw_price[:close_time],
# 							 updated_at: DateTime.now)
# 	else 
# 		ven_eth = VenEth.new(opening_time: raw_price[:open_time], 
# 							 closing_price: raw_price[:close_price], 
# 							 closing_time: raw_price[:close_time],
# 							 created_at: DateTime.now,
# 							 updated_at: DateTime.now)
# 		ven_eth.save
# 	end
# end

# (1..3).each do |i|
# 	earliest_time_row = FunEth.order(:opening_time).first
# 	if earliest_time_row && earliest_time_row.opening_time
# 		raw_price_history = bot.price_history_with_end_time("FUNETH", '5m', 500, earliest_time_row.opening_time)
# 	else
# 		raw_price_history = bot.price_history("FUNETH", '5m', 500)
# 	end

# 	raw_price_history.each do |raw_price|
# 		ven_eth = FunEth.where(opening_time: raw_price[:open_time])
# 		if ven_eth && ven_eth.first
# 			ven_eth.first.update(opening_time: raw_price[:open_time], 
# 								 closing_price: raw_price[:close_price], 
# 								 closing_time: raw_price[:close_time],
# 								 updated_at: DateTime.now)
# 		else 
# 			ven_eth = FunEth.new(opening_time: raw_price[:open_time], 
# 								 closing_price: raw_price[:close_price], 
# 								 closing_time: raw_price[:close_time],
# 								 created_at: DateTime.now,
# 								 updated_at: DateTime.now)
# 			ven_eth.save
# 		end
# 	end
# end

# b = BackTester.new
# b.go



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