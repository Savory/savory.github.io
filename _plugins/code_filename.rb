# Makes ```ts src/app.module.ts work.
#
# Kramdown's fenced-block parser only accepts a single \w+ after the backticks,
# so a fence carrying a filename is not recognised as a code block at all — the
# code leaks into the page as prose, and backticks inside it get re-parsed as
# inline code. This hook runs before the markdown converter and splits the info
# string in two: the language stays on the fence, the filename becomes a raw
# HTML block just above it, which kramdown passes through untouched.
#
#     ```ts src/app.module.ts        <div class="code-file">src/app.module.ts</div>
#     import { Module } from ...  →
#     ```                            ```ts
#                                    import { Module } from ...
#                                    ```
#
# Styling lives in _sass/savory/_code.scss, which glues the two into one block.
module Savory
  module CodeFilename
    # Opening fence: up to 3 spaces of indent, 3+ backticks or tildes, a word
    # for the language, then anything else — that "anything else" is the label.
    FENCE_OPEN = /\A(\s{0,3})(`{3,}|~{3,})[ \t]*([\w+#-]+)[ \t]+(\S.*?)[ \t]*\z/

    def self.process(content)
      return content unless content.include?("```") || content.include?("~~~")

      out = []
      fence = nil # [marker_char, length] while inside a block

      content.each_line do |line|
        stripped = line.chomp

        if fence
          # Only a run of the same character, at least as long, closes a block.
          char, len = fence
          fence = nil if stripped =~ /\A\s{0,3}#{Regexp.escape(char)}{#{len},}[ \t]*\z/
          out << line
          next
        end

        if (m = FENCE_OPEN.match(stripped))
          indent, marker, lang, label = m.captures
          fence = [marker[0], marker.length]
          out << "\n" unless out.empty? || out.last.strip.empty?
          out << %(#{indent}<div class="code-file">#{escape(label)}</div>\n)
          out << "\n"
          out << "#{indent}#{marker}#{lang}\n"
          next
        end

        # A fence with no label still opens a block we must not look inside.
        if stripped =~ /\A\s{0,3}(`{3,}|~{3,})/
          marker = Regexp.last_match(1)
          fence = [marker[0], marker.length]
        end

        out << line
      end

      out.join
    end

    def self.escape(text)
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end
  end
end

Jekyll::Hooks.register [:documents, :pages], :pre_render do |doc|
  doc.content = Savory::CodeFilename.process(doc.content) if doc.content
end
