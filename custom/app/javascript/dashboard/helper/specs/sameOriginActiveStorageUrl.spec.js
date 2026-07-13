import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { toSameOriginActiveStorageUrl } from '../sameOriginActiveStorageUrl';

describe('toSameOriginActiveStorageUrl', () => {
  beforeEach(() => {
    vi.stubGlobal('location', {
      origin: 'https://dev-chat.example.com',
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('rewrites cross-origin Active Storage URLs to the current origin', () => {
    const url =
      'https://chat.example.com/rails/active_storage/blobs/redirect/token/media.jpg';

    expect(toSameOriginActiveStorageUrl(url)).toBe(
      'https://dev-chat.example.com/rails/active_storage/blobs/redirect/token/media.jpg'
    );
  });

  it('keeps same-origin Active Storage URLs unchanged', () => {
    const url =
      'https://dev-chat.example.com/rails/active_storage/blobs/redirect/token/media.jpg';

    expect(toSameOriginActiveStorageUrl(url)).toBe(url);
  });

  it('keeps external non-Active-Storage URLs unchanged', () => {
    const url = 'https://cdn.instagram.com/image.jpg';

    expect(toSameOriginActiveStorageUrl(url)).toBe(url);
  });

  it('returns falsy values as-is', () => {
    expect(toSameOriginActiveStorageUrl(null)).toBeNull();
    expect(toSameOriginActiveStorageUrl('')).toBe('');
    expect(toSameOriginActiveStorageUrl(undefined)).toBeUndefined();
  });
});
