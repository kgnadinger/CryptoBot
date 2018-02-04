require './bot'
Dir["./models/*.rb"].each {|file| require file }
require 'sequel'
require './back_tester'
require 'gruff'
require('indicators')

bot = BinanceBot.new

# Uncomment to start live trading bot (old trading bot)
# bot.stream

# Uncomment to start live trading
# Uncomment 1 line at a time, each stream goes into its own tab on console
# bot.fun_stream
# bot.wtc_stream
# bot.ven_stream
# bot.trx_stream
# bot.amb_stream
bot.xlm_stream

# Uncomment lines 20-47 to download historical prices for a coin pair
# Replace the symbols with coin of choice and model names with coin of choice
# Example: "VENETH" and VenEth
# def download_historical_prices
# 	bot = BinanceBot.new
# 	(1..30).each do |i|
# 		earliest_time_row = XlmEth.order(:opening_time).first
# 		if earliest_time_row && earliest_time_row.opening_time
# 			raw_price_history = bot.price_history_with_end_time("XLMETH", '5m', 500, earliest_time_row.opening_time)
# 		else
# 			raw_price_history = bot.price_history("XLMETH", '5m', 500)
# 		end

# 		raw_price_history.each do |raw_price|
# 			coin_eth = XlmEth.where(opening_time: raw_price[:open_time])
# 			if coin_eth && coin_eth.first
# 				coin_eth.first.update(opening_time: raw_price[:open_time], 
# 									 closing_price: raw_price[:close_price], 
# 									 closing_time: raw_price[:close_time],
# 									 updated_at: DateTime.now)
# 			else 
# 				coin_eth = XlmEth.new(opening_time: raw_price[:open_time], 
# 									 closing_price: raw_price[:close_price], 
# 									 closing_time: raw_price[:close_time],
# 									 created_at: DateTime.now,
# 									 updated_at: DateTime.now)
# 				coin_eth.save
# 			end
# 		end
# 	end
# end
# download_historical_prices

# Uncomment next 2 lines to initliaze BackTester which can be found in back_tester.rb
# Replace WtcEth with coin pair of choice, replace number in limit() with how far back you want to go
# coinEthArray = WtcEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(5000).all.sort { |d,e| d.opening_time <=> e.opening_time }
# b = BackTester.new coin_array: coinEthArray

# Uncoment to use the calibrate a variable in back_tester(with previous 2 lines uncommented)
# b.calibrate

# Uncomment to use the main back tester in back_tester.rb, as before, uncomment the 2 set up lines
# b.go

# bot.stream
