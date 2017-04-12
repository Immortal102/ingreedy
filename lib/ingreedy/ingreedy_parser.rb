require "parslet"

require_relative "amount_parser"
require_relative "rationalizer"
require_relative "root_parser"
require_relative "unit_variation_mapper"

module Ingreedy
  class Parser
    attr_reader :original_query

    Result = Struct.new(
      :amount,
      :unit,
      :container_amount,
      :container_unit,
      :ingredient,
      :original_query,
    )

    def initialize(original_query)
      @original_query = spaces_cleaned(original_query)
    end

    def parse
      result = Result.new
      result.original_query = original_query

      begin
        parslet = RootParser.new(original_query).parse

        result.amount = rationalize(parslet[:amount])
        result.amount = [
          result.amount,
          rationalize(parslet[:amount_end])
        ] if parslet[:amount_end]

        result.container_amount = rationalize(parslet[:container_amount])

        result.unit = convert_unit_variation_to_canonical(
          parslet[:unit].to_s,
        ) if parslet[:unit]

        result.container_unit = convert_unit_variation_to_canonical(
          parslet[:container_unit].to_s,
        ) if parslet[:container_unit]

        result.ingredient = cleaned_ingredient(parslet[:ingredient].to_s)

        with_handling_errors_for(result)
      rescue Parslet::ParseFailed => e
        if after_error_callback
          after_error_callback.call(e, result)
        else
          fail ParseFailed.new(e.message), e.backtrace
        end
      end
    end

    private

    def after_error_callback
      Ingreedy.after_error
    end

    def cleaned_ingredient(ingr_str)
      # clean from trailing spaces + return empty string when there are only spaces or empty array (parslet returns [] when the ingredient is empty)
      ingr_str.strip.gsub(/^(\[\]|\s+)$/, '')
    end

    def cleaned_amount(amount_str)
      amount_str.gsub(/[\(\)\'\"]/, '')
    end

    def spaces_cleaned(str)
      # replace all the multiple spaces with single one + spases from beginning and end
      str.gsub(/\s+/, ' ').strip
    end

    def convert_unit_variation_to_canonical(unit_variation)
      return if unit_variation.empty?
      UnitVariationMapper.unit_from_variation(unit_variation)
    end

    def rationalize(amount)
      return unless amount
      integer = amount[:integer_amount]
      integer &&= cleaned_amount(integer.to_s)

      float = amount[:float_amount]
      float &&= cleaned_amount(float.to_s)

      fraction = amount[:fraction_amount]
      fraction &&= cleaned_amount(fraction.to_s)

      word = amount[:word_integer_amount]
      word &&= cleaned_amount(word.to_s)

      Rationalizer.rationalize(
        integer: integer,
        float: float,
        fraction: fraction,
        word: word,
      )
    end

    def with_handling_errors_for(result)
      return result unless after_error_callback
      raise_or result
    end

    def raise_or(result)
      if result.amount.nil?
        raise EmptyAmount.new('amount is not present')
      # if the ingredient contains numbers or it is empty than we consider such ingredient string was parsed incorrectly
      elsif result.ingredient.empty? || result.ingredient.match(/(\d)/)
        raise IncorrectIngredient.new('ingredient looks as incorrect')
      else
        result
      end
    end
  end
end
