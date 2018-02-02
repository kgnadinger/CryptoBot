Dir["./models/*.rb"].each {|file| require file }
require('./bot')
require('linear-regression')
require('matrix')

class RsiAlgorithm

	attr_reader :price_history
	attr_reader :last_rsi

	def rsi_is_a_valley?(rsiArray, index)
		if rsiArray[index - 1] && rsiArray[index + 1]
			first = rsiArray[index - 1]
			last = rsiArray[index + 1]
			if first >= rsiArray[index] && last >= rsiArray[index]
				true
			else
				false
			end
		else
			false
		end
	end

	def rsi_is_a_peak?(rsiArray, index)
		if rsiArray[index - 1] && rsiArray[index + 1]
			first = rsiArray[index - 1]
			last = rsiArray[index + 1]
			if first <= rsiArray[index] && last <= rsiArray[index]
				true
			else
				false
			end
		else
			false
		end
	end

	def initialize(rsiTolerance: 10, price_history: [], buy_zone: 30, sell_zone: 70)
		@rsiTolerance = rsiTolerance
		@price_history = price_history
		@buy_zone = buy_zone
		@sell_zone = sell_zone
		@last_rsi = ""
	end

	# format the number to make sure I dont run into floating point issues
	def format_number_to_be_larger_than_one(number)
		if (number < 1 && number > 0) || (number < 0 && number > -1)
			number = number * 10
			format_number_to_be_larger_than_one(number)
		else
			number.to_f
		end
	end

	def macd_recently_crossed?(macdArray)

		# formatting the last and 2nd to last histogram height
		firstMacd = format_number_to_be_larger_than_one(macdArray[macdArray.length - 2][0])
		nextMacd = format_number_to_be_larger_than_one(macdArray[macdArray.length - 1][0])

		# divide the 2 to see if there was a switch in sign. 
		# If it went from negative to positive, then the result of the division would negative
		# If it went from positive to negative, then the result of the division would also be negative
		# If it stayed the same sign, then the result of the division would be positive
		if ((firstMacd / nextMacd) < 0)
			true
		else
			false
		end
	end

	def average_slope_of_array(array)
		slopes = []
		array.each_with_index do |a, index|
			if index != 0
				slope = (array[index] - array[index - 1]).to_f
				slopes.push(slope)
			end
		end
		average_slope = slopes.reduce(:+) / slopes.count
		format_number_to_be_larger_than_one(average_slope)
	end

	def regress x, y, degree
	  x_data = x.map { |xi| (0..degree).map { |pow| (xi**pow).to_f } }
	 
	  mx = Matrix[*x_data]
	  my = Matrix.column_vector(y)
	 
	  ((mx.t * mx).inv * mx.t * my).transpose.to_a[0]
	end

	# just simply calculating whether or not the last 4 rsi numbers crossed into either threshold
	# rsi will always cross before macd which is why I test a few places backwards
	def rsi_recently_crossed_threshold?(rsiArray)
		crossed = false
		buy = false
		sell = false
		last_index = rsiArray.count - 1
		buyRsiToInspect = []
		sellRsiToInspect = []

		# Inspect the last indexes in rsiArray(up to @tolerance) to see if they crossed the
		# buy and sell zones
		rsiToInspect = rsiArray[(last_index - @rsiTolerance)..last_index]
		rsiToInspect.each_with_index do |rsi, index|
			if rsi >= @sell_zone && rsi_is_a_peak?(rsiToInspect, index)
				crossed = true
				sell = true
				sellRsiToInspect.push(rsi)
			elsif rsi <= @buy_zone && rsi_is_a_valley?(rsiToInspect, index)
				buy = true
				crossed = true
				buyRsiToInspect.push(rsi)
			end
		end

		if buy
			if buyRsiToInspect.count > 1
				# is it trending up? Then buy
				xs = (1..buyRsiToInspect.count).map { |n| n }
				# quad_regression_sign = regress(xs, buyRsiToInspect, 2).last
				linear_regression = Regression::Linear.new(xs, buyRsiToInspect)
				if linear_regression.slope > 0
				# if quad_regression_sign > 0
					{ crossed: true, sell: false, buy: true }
				else
					{ crossed: true, sell: false, buy: false }
				end
			else
				{ crossed: true, sell: false, buy: false }
			end
		elsif sell
			if sellRsiToInspect.count > 1
				# is it trending down? Then sell
				# average_slope = average_slope_of_array(sellRsiToInspect)
				xs = (1..sellRsiToInspect.count).map { |n| n }
				# quad_regression_sign = regress(xs, sellRsiToInspect, 2).last
				linear_regression = Regression::Linear.new(xs, sellRsiToInspect)
				# if quad_regression_sign < 0
				if linear_regression.slope < 0
					{ crossed: true, sell: true, buy: false }
				else
					{ crossed: true, sell: false, buy: false }
				end
			else
				{ crossed: true, sell: false, buy: false }
			end
		else
			{ crossed: true, sell: false, buy: false }
		end
	end



	def analyze

		# Initialize Indicator Class
		data = Indicators::Data.new(@price_history)


		# calculate MACD
		macdArray = data.calc(:type => :macd, :params => [12, 26, 9]).output

		# reference to rsi so I know whether to buy or sell
		# rsiAlert = rsi_recently_crossed_threshold?(rsi)

		# test to see if rsi went to the buy/sell zones and a macd cross
		if true #macd_recently_crossed?(macdArray)
			# calculate rsi
			rsi = data.calc(:type => :rsi, :params => 14).output
			rsiAlert = rsi_recently_crossed_threshold?(rsi)
			if rsiAlert[:crossed]
				if rsiAlert[:buy]
					puts "RSI Buy Alert: #{rsiAlert}"
					"buy"
				elsif rsiAlert[:sell]
					puts "RSI Sell Alert: #{rsiAlert}"
					"sell"
				else
					"wait"
				end
			else
				"wait"
			end
		else
			"wait"
		end
	end

end