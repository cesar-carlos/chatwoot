# frozen_string_literal: true

# FORK: ViteRuby may skip production rebuild when only custom/app/javascript
# changed (digest misses overlay paths). Invalidate the last-build stamp when
# any custom JS/Vue file is newer than the stamp so assets:precompile /
# vite:build always pick up fork frontend changes.
namespace :fork do
  desc 'Invalidate Vite last-build stamp when custom JS is newer'
  task invalidate_vite_stamp_if_custom_js_changed: :environment do
    stamp = Rails.root.join('tmp/cache/vite/last-build-production.json')
    custom_js_root = Rails.root.join('custom/app/javascript')
    next unless custom_js_root.directory?

    newest_mtime = Dir.glob(custom_js_root.join('**/*.{js,vue,ts,tsx,css}')).filter_map do |path|
      File.mtime(path) if File.file?(path)
    end.max
    next if newest_mtime.blank?

    if stamp.exist? && File.mtime(stamp) >= newest_mtime
      Rails.logger.info('[FORK] vite stamp up to date relative to custom/app/javascript')
      next
    end

    FileUtils.rm_f(stamp)
    Rails.logger.info('[FORK] removed vite last-build-production.json (custom JS newer)')
  end
end

# Run before the stock assets:precompile / vite:build chain.
Rake::Task['assets:precompile'].enhance(['fork:invalidate_vite_stamp_if_custom_js_changed']) if Rake::Task.task_defined?('assets:precompile')

Rake::Task['vite:build'].enhance(['fork:invalidate_vite_stamp_if_custom_js_changed']) if Rake::Task.task_defined?('vite:build')
