require 'rails_helper'

RSpec.describe Custom::MessageSearch::Tsquery do
  describe '.build_phrase_query' do
    it 'joins terms with AND so words can appear in any order' do
      expect(described_class.build_phrase_query('fix contract')).to eq('fix & contract')
    end

    it 'strips tsquery special characters from terms' do
      expect(described_class.build_phrase_query('fix | contract')).to eq('fix & contract')
    end

    it 'returns blank for empty input' do
      expect(described_class.build_phrase_query('   ')).to eq('')
    end
  end
end
