class ImportParser
  module Strategies
    class CSV
      def parse(string)
        rows = ::CSV.parse(string, headers: true)
        {
          headers: rows.headers,
          rows: rows.map(&:to_hash)
        }
      end
    end
  end
end
