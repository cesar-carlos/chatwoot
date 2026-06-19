import { foldDiacritics, textIncludesFoldedQuery } from '../messageSearchText';

describe('messageSearchText', () => {
  describe('foldDiacritics', () => {
    it('lowercases and removes diacritics', () => {
      expect(foldDiacritics('Contráto')).toBe('contrato');
      expect(foldDiacritics('São Paulo')).toBe('sao paulo');
    });
  });

  describe('textIncludesFoldedQuery', () => {
    it('matches accent-insensitive substrings', () => {
      expect(textIncludesFoldedQuery('revisar o contráto', 'contrato')).toBe(
        true
      );
      expect(textIncludesFoldedQuery('hello world', 'contrato')).toBe(false);
    });

    it('returns false for queries shorter than 2 characters', () => {
      expect(textIncludesFoldedQuery('ab', 'a')).toBe(false);
    });
  });
});
