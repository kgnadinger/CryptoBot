Dir["./models/*.rb"].each {|file| require file }
require('./bot')
require('gruff')
require('spreadsheet')

class BackTester

	# these are suggested variables you can test on coin pairs using calibrate
	# coin_array is the coin history you include when you intialize the class in main.rb
	def initialize(coin_array: [])
		@trading_fee = 0.0005
		@percentage_to_buy_with = 0.01
		@percentage_to_sell_with = 0.25
		@sell_zone = 70
		@buy_zone = 30
		@price_multiplier = 1.13
		@trading_range = 0.08
		@coin_array = coin_array
	end

	# this is an example of calibrating a variable, here I am calibrating @sell_zone
	# I start at 65 (in the initiliazer) and then increment the sell zone by 1 and see if the
	# new ammount is greater than the last, I log to the console which sell zone is the best
	# at the end
	def calibrate
		increase = 0
		buy_sell_zone = { buy: @buy_zone, sell: @sell_zone }
		(1..10).each do |t|
			amount = self.go
			if amount > increase
				increase = amount
				buy_sell_zone = { buy: @buy_zone, sell: @sell_zone }
			end
			puts "Amount: #{increase}, Buy Zone: #{@buy_zone} Sell Zone: #{@sell_zone}"
			@sell_zone -= 1
		end
		puts "Final Amount: #{increase}, Buy Zone: #{buy_sell_zone[:buy]} Sell Zone: #{buy_sell_zone[:sell]}"
	end

	def go
		# starting coin
		coin_amount = 0

		# starting eth
		eth_amount = 1

		# going to buy with 10% of the amount of eth left
		eth_trading_chunks = eth_amount * @percentage_to_buy_with

		# Grab all CoinEth, ordered from smallest opening_time(integer)
		coinEthArray = @coin_array

		# used to maximize profits by selling at a price point
		recently_bought = false
		recently_bought_price = 0.0
		recently_bought_index = 1

		recently_sold = false
		recently_sold_price = 0.0

		# used to report daily % increases
		daily_increases = []
		last_day_amount = 0

		x_values = []
		buy_x_values = []
		sell_x_values = []
		y_values = []
		buy_y_values = []
		sell_y_values = []

		trying_to_buy = false
		buy_limit = 0.0
		buy_ceiling = 0.0

		trying_to_sell = false
		sell_limit = 0.0
		sell_floor = 0.0

		coinEthArray.each_with_index do |ven_eth, index|
			coin_trading_chunks = coin_amount * @percentage_to_sell_with
			# starting at 34 because that's how much price data I need to use the indicators
			if index > 34
				# array of just prices
				price_history = coinEthArray[0, index + 1].map { |coin| coin.closing_price }

				# chop to length of 250, optimization
				if price_history.count > 500
					price_history = price_history[index - 500, index]
				end

				# initialize algorithm to determine buy or sell
				algorithm = RsiAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: @buy_zone, sell_zone: @sell_zone
				signal = algorithm.analyze

				if trying_to_buy
					if ven_eth[:closing_price] > buy_ceiling
						buy_x_values.push(index)
						buy_y_values.push(price_history.last)

						# "withdraw" the eth that I'm buying with
						eth_amount = eth_amount - eth_trading_chunks

						# amount of ven I'm gaining = amount of eth I'm buying with / price all times 0.0095 which is the amount with the fee taken out
						new_ven = (eth_trading_chunks / ven_eth[:closing_price]).ceil * (1 - @trading_fee)
						coin_amount += new_ven

						# keep track that I recently bought so I can sell at a high price
						recently_bought = true
						recently_bought_price = ven_eth[:closing_price]
						trying_to_buy = false
						puts "New Fun Amount: #{coin_amount}, Price: #{coin_amount * ven_eth[:closing_price].round(10)}, Index: #{index}"
					elsif ven_eth[:closing_price] < buy_limit
						buy_ceiling = ven_eth[:closing_price] * (1 + (@trading_range / 2.0))
						buy_limit = ven_eth[:closing_price] * (1 - (@trading_range / 2.0))
						if price_history.last
							x_values.push(index)
							y_values.push(price_history.last)
						end
					else
						if price_history.last
							x_values.push(index)
							y_values.push(price_history.last)
						end
					end
				elsif trying_to_sell
					if ven_eth[:closing_price] < sell_floor
						sell_x_values.push(index)
						sell_y_values.push(price_history.last)
						# "withdraw" the ven I'm selling
						coin_amount = coin_amount - coin_trading_chunks.floor

						# price of ven I'm selling in terms of eth
						sell_amount = coin_trading_chunks.floor * ven_eth[:closing_price]

						# take out the fee
						new_eth = sell_amount * (1 - @trading_fee)
						eth_amount += new_eth
						recently_bought = false
						trying_to_sell = false
						puts "New Eth Amount(protecting profits): #{eth_amount}, Price: #{ven_eth[:closing_price].round(10)}, Index: #{index}"
					elsif ven_eth[:closing_price] > sell_limit
						sell_floor = ven_eth[:closing_price] * (1 - (@trading_range / 2.0))
						sell_limit = ven_eth[:closing_price] * (1 + (@trading_range / 2.0))
						if price_history.last
							x_values.push(index)
							y_values.push(price_history.last)
						end
					else
						if price_history.last
							x_values.push(index)
							y_values.push(price_history.last)
						end
					end
				elsif signal == "buy"
					# make sure I have enough eth to buy with
					if eth_amount - eth_trading_chunks > 0
						trying_to_buy = true
						buy_ceiling = ven_eth[:closing_price]
						buy_limit = ven_eth[:closing_price] * (1 - @trading_range)						
					else
						puts "Ran out of Eth"
					end
				# elsif recently_bought
				# 	# sell if the price reaches the recently bought price multiplied up (usually 1.1 - 1.5 or 10% - 50% higher)
				# 	if ven_eth[:closing_price] > recently_bought_price * @price_multiplier
				# 		trying_to_sell = true
				# 		sell_floor = ven_eth[:closing_price]
				# 		sell_limit = ven_eth[:closing_price] * (1 + @trading_range)
				# 	else
				# 		if price_history.last
				# 			x_values.push(index)
				# 			y_values.push(price_history.last)
				# 		end
				# 	end
				elsif signal == "sell"
					# puts "Selling - RSI: buy: #{rsiAlert[:buy]}, sell: #{rsiAlert[:sell]}"
					if coin_amount - coin_trading_chunks.floor > 0
						trying_to_sell = true
						sell_floor = ven_eth[:closing_price]
						sell_limit = ven_eth[:closing_price] * (1 + @trading_range)
					else
						puts "Ran out of VEN"
					end
				else
					if price_history.last
						x_values.push(index)
						y_values.push(price_history.last)
					end
				end
			end
			# used to calculate daily increase %
			if index % 288 == 0
				if last_day_amount != 0
					total_eth_amount = eth_amount + (coin_amount * ven_eth[:closing_price])
					if total_eth_amount - last_day_amount != 0
						change_in_eth = (total_eth_amount - last_day_amount).to_f / last_day_amount
						daily_increases.push(change_in_eth)
						last_day_amount = total_eth_amount
					end
				else
					last_day_amount = eth_amount
				end
			end
		end
		puts "Ven Amount = #{coin_amount}, Price in Eth = #{coin_amount * coinEthArray.last[:closing_price]}"
		puts "Eth Amount = #{eth_amount}}"
		total = 0
		daily_increases.each do |d|
			total += d
		end
		if daily_increases.count > 0
			puts "Increase/Decrease = #{(total / daily_increases.count) * 100}%"
		end
		full_amount = eth_amount + (coin_amount * coinEthArray.last[:closing_price])
		puts "Full Eth Amount = #{full_amount}}"

		g = Gruff::Scatter.new(size=2000)
		g.circle_radius = 3
		g.title = "Test"
		g.data(:price, x_values, y_values)
		g.data(:buy, buy_x_values, buy_y_values) unless buy_x_values.count == 0
		g.data(:sell, sell_x_values, sell_y_values) unless sell_x_values.count == 0
		g.write('test.png')
		full_amount
		
	end
	
end