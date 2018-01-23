require './bot'
Dir["./models/*.rb"].each {|file| require file }
require 'sequel'
require './back_tester'
require 'gruff'

bot = BinanceBot.new

# g = Gruff::Line.new(600)
# g.title = 'FUNETH BackTester'
# prices = FunEth.order(:opening_time).select(:id, :closing_price).all.map { |f| f.closing_price }
# g.data("FunEth", prices)
# price_hash = {}
# FunEth.order(:opening_time).select(:id, :closing_price).all.each_with_index do |f, index|
# 	price_hash[index] = f.closing_time
# end
# g.labels = price_hash
# g.write('exciting.png')
# puts bot.getAmount("FUN")

# info = bot.account_info
# eth_hash = {}
# fun_hash = {}
# bot.account_info["balances"].each do |b|
# 	if b["asset"] == "ETH"
# 		eth_hash = b
# 	end
# 	if b["asset"] == "FUN"
# 		fun_hash = b
# 	end
# end
# puts eth_hash["free"]
# puts fun_hash["free"]

# bot.create_order("FUNETH", "sell", "MARKET", 1)



# create_test_order(symbol, side, type="MARKET", quantity)

# bot.stream

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

# (1..30).each do |i|
# 	earliest_time_row = WtcEth.order(:opening_time).first
# 	if earliest_time_row && earliest_time_row.opening_time
# 		raw_price_history = bot.price_history_with_end_time("WTCETH", '5m', 500, earliest_time_row.opening_time)
# 	else
# 		raw_price_history = bot.price_history("WTCETH", '5m', 500)
# 	end

# 	raw_price_history.each do |raw_price|
# 		ven_eth = WtcEth.where(opening_time: raw_price[:open_time])
# 		if ven_eth && ven_eth.first
# 			ven_eth.first.update(opening_time: raw_price[:open_time], 
# 								 closing_price: raw_price[:close_price], 
# 								 closing_time: raw_price[:close_time],
# 								 updated_at: DateTime.now)
# 		else 
# 			ven_eth = WtcEth.new(opening_time: raw_price[:open_time], 
# 								 closing_price: raw_price[:close_price], 
# 								 closing_time: raw_price[:close_time],
# 								 created_at: DateTime.now,
# 								 updated_at: DateTime.now)
# 			ven_eth.save
# 		end
# 	end
# end
funEthArray = WtcEth.order(:opening_time).select(:id, :closing_price).all
b = BackTester.new coin_array: funEthArray
b.calibrate



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