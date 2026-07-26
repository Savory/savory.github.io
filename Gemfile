source "https://rubygems.org"

# The site is built by .github/workflows/pages.yml, not by GitHub Pages' stock
# pipeline. That is what makes _plugins/ run — the stock pipeline ignores it.
gem "jekyll", "~> 4.4"

group :jekyll_plugins do
  gem "jekyll-remote-theme"
  gem "jekyll-paginate"
  gem "jekyll-sitemap"
  gem "jekyll-gist"
  gem "jekyll-feed"
  gem "jemoji"
  gem "jekyll-include-cache"
end

# No longer in Ruby's default gems, but still needed by Jekyll's dependencies.
gem "csv"
gem "base64"
gem "bigdecimal"
gem "logger"

gem "tzinfo-data", platforms: [:mingw, :mswin, :x64_mingw, :jruby]
gem "wdm", "~> 0.1.0", platforms: [:mingw, :mswin, :x64_mingw]