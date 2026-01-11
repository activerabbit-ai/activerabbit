module MarkdownHelper
  def render_markdown(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener" }
    )

    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      highlight: true,
      no_intra_emphasis: true
    )

    raw markdown.render(text)
  end

  def render_ai_summary(text)
    return "" if text.blank?

    renderer = CustomAIRenderer.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener" }
    )

    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      highlight: true,
      no_intra_emphasis: true
    )

    raw markdown.render(text)
  end

  # Custom renderer for AI summaries with beautiful styling
  class CustomAIRenderer < Redcarpet::Render::HTML
    def header(text, level)
      icon = case text.downcase
             when /root cause/
               '<span class="inline-flex items-center justify-center w-7 h-7 rounded-lg bg-red-100 text-red-600 mr-2">🔍</span>'
             when /fix/
               '<span class="inline-flex items-center justify-center w-7 h-7 rounded-lg bg-emerald-100 text-emerald-600 mr-2">🔧</span>'
             when /prevention/
               '<span class="inline-flex items-center justify-center w-7 h-7 rounded-lg bg-amber-100 text-amber-600 mr-2">🛡️</span>'
             else
               ''
             end

      case level
      when 1
        %(<h1 class="text-xl font-bold text-slate-900 mt-4 mb-3 flex items-center">#{icon}#{text}</h1>)
      when 2
        %(<h2 class="text-lg font-bold text-slate-800 mt-6 mb-3 pb-2 border-b border-slate-200 flex items-center">#{icon}#{text}</h2>)
      when 3
        %(<h3 class="text-base font-semibold text-slate-700 mt-4 mb-2">#{text}</h3>)
      else
        %(<h#{level} class="font-semibold text-slate-700 mt-3 mb-2">#{text}</h#{level}>)
      end
    end

    def paragraph(text)
      %(<p class="mb-4 leading-relaxed text-slate-700 text-sm">#{text}</p>)
    end

    def list(contents, list_type)
      tag = list_type == :ordered ? "ol" : "ul"
      list_class = list_type == :ordered ? "list-decimal" : "list-disc"
      %(<#{tag} class="my-4 pl-5 #{list_class} space-y-2 text-sm text-slate-700">#{contents}</#{tag}>)
    end

    def list_item(text, list_type)
      %(<li class="leading-relaxed">#{text}</li>)
    end

    def block_code(code, language)
      lang = language || "ruby"
      %(
        <div class="my-4 rounded-xl overflow-hidden border border-slate-700 shadow-lg">
          <div class="bg-slate-800 px-4 py-2 flex items-center gap-2 border-b border-slate-700">
            <span class="w-3 h-3 rounded-full bg-red-500"></span>
            <span class="w-3 h-3 rounded-full bg-yellow-500"></span>
            <span class="w-3 h-3 rounded-full bg-green-500"></span>
            <span class="ml-2 text-xs text-slate-400 font-mono">#{lang}</span>
          </div>
          <pre class="bg-slate-900 text-slate-100 p-4 overflow-x-auto text-sm leading-relaxed font-mono m-0"><code>#{ERB::Util.html_escape(code)}</code></pre>
        </div>
      )
    end

    def codespan(code)
      %(<code class="bg-indigo-50 text-indigo-700 px-1.5 py-0.5 rounded-md text-sm font-mono font-medium">#{ERB::Util.html_escape(code)}</code>)
    end

    def double_emphasis(text)
      %(<strong class="font-semibold text-slate-800">#{text}</strong>)
    end

    def emphasis(text)
      %(<em class="italic text-slate-600">#{text}</em>)
    end

    def block_quote(quote)
      %(<blockquote class="border-l-4 border-indigo-400 bg-indigo-50/50 pl-4 py-2 my-4 text-sm text-slate-600 italic">#{quote}</blockquote>)
    end
  end
end

