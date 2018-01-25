Dir["./models/*.rb"].each {|file| require file }
require('./bot')

class BackTester

	def initialize(coin_array: [])
		@trading_fee = 0.0005
		@percentage_to_buy_with = 0.01
		@percentage_to_sell_with = 0.5
		@calculating_length = 500
		@sell_zone = 65
		@buy_zone = 35
		@price_multiplier = 1.13
		@coin_array = coin_array
	end

	def calibrate
		increase = 0
		sell_zone = @sell_zone
		(1..10).each do |t|
			amount = self.go
			if amount > increase
				increase = amount
				sell_zone = @sell_zone
			end
			puts "Amount: #{increase}, Sell Zone: #{@sell_zone}"
			@sell_zone += 1
		end
		puts "Final Amount: #{increase}, Sell Zone: #{sell_zone}"
	end

	def go
		# starting ven
		ven_amount = 0

		# starting eth
		eth_amount = 1

		# going to buy with 10% of the amount of eth left
		eth_trading_chunks = eth_amount * @percentage_to_buy_with

		# Grab all VenEth, ordered from smallest opening_time(integer)
		venEthArray = @coin_array

		recently_bought = false
		recently_bought_price = 0.0
		recently_bought_index = 1

		daily_increases = []
		last_day_amount = 0

		venEthArray.each_with_index do |ven_eth, index|
			# starting at 34 because that's how much price data I need to use the indicators
			ven_trading_chunks = ven_amount * @percentage_to_sell_with
			if index > 34
				price_history = venEthArray[0, index + 1].map { |eth| eth.closing_price }

				if price_history.count > 251
					price_history = price_history[index - 250, index]
				end
				algorithm = RsiMacdAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: @buy_zone, sell_zone: @sell_zone
				
				if algorithm.analyze == "buy"
					# make sure I have enough eth to buy with
					if eth_amount - eth_trading_chunks > 0

						# "withdraw" the eth that I'm buying with
						eth_amount = eth_amount - eth_trading_chunks

						# amount of ven I'm gaining = amount of eth I'm buying with / price all times 0.0095 which is the amount with the fee taken out
						new_ven = (eth_trading_chunks / ven_eth[:closing_price]).ceil * (1 - @trading_fee)
						ven_amount += new_ven
						recently_bought = true
						recently_bought_price = ven_eth[:closing_price]
						puts "New Fun Amount: #{ven_amount}, Price: #{ven_amount * ven_eth[:closing_price]}, Index: #{index}"
					else
						puts "Ran out of Eth"
					end
				elsif recently_bought
					if ven_eth[:closing_price] > recently_bought_price * @price_multiplier
						recently_bought = false
						sell_amount = ven_amount.floor * ven_eth[:closing_price]
						new_eth = sell_amount * (1 - @trading_fee)
						eth_amount += new_eth
						puts "New Eth Amount(protecting profits): #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
					end
					# elsif index - recently_bought_index > 5
					# 	if ven_eth[:closing_price] < recently_bought_price * @stop_loss_percentage
					# 		# "withdraw" the ven I'm selling
					# 		ven_amount = ven_amount - ven_trading_chunks.floor

					# 		# price of ven I'm selling in terms of eth
					# 		sell_amount = ven_trading_chunks.floor * ven_eth[:closing_price]

					# 		# take out the fee
					# 		new_eth = sell_amount * (1 - @trading_fee)
					# 		eth_amount += new_eth
					# 		recently_bought = false
					# 		puts "New Eth Amount(stopping loss): #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
					# 	end
					# end				
				elsif algorithm.analyze == "sell"
					# puts "Selling - RSI: buy: #{rsiAlert[:buy]}, sell: #{rsiAlert[:sell]}"
					if ven_amount - ven_trading_chunks.floor > 0

						# "withdraw" the ven I'm selling
						ven_amount = ven_amount - ven_trading_chunks.floor

						# price of ven I'm selling in terms of eth
						sell_amount = ven_trading_chunks.floor * ven_eth[:closing_price]

						# take out the fee
						new_eth = sell_amount * (1 - @trading_fee)
						eth_amount += new_eth
						recently_bought = false
						puts "New Eth Amount: #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
					else
						puts "Ran out of VEN"
					end
				end
			end
			if index % 288 == 0
				if last_day_amount != 0
					total_eth_amount = eth_amount + (ven_amount * ven_eth[:closing_price])
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
		puts "Ven Amount = #{ven_amount}, Price in Eth = #{ven_amount * venEthArray.last[:closing_price]}"
		puts "Eth Amount = #{eth_amount}}"
		total = 0
		daily_increases.each do |d|
			total += d
		end
		if daily_increases.count > 0
			puts "Increase/Decrease = #{(total / daily_increases.count) * 100}%"
		end
		full_amount = eth_amount + (ven_amount * venEthArray.last[:closing_price])
		full_amount
		
	end
	
end