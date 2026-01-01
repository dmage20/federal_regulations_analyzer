module ApplicationHelper
  def ecfr_link_helper(ref)
    title = ref["title"]
    chapter = ref["chapter"]
    subtitle = ref["subtitle"]

    base_url = "https://www.ecfr.gov/current/title-#{title}"

    if chapter.present?
      {
        url: "#{base_url}/chapter-#{chapter}",
        label: "#{title} #{chapter}"
      }
    elsif subtitle.present?
      {
        url: "#{base_url}/subtitle-#{subtitle}",
        label: "#{title} #{subtitle}"
      }
    else
      {
        url: base_url,
        label: title.to_s
      }
    end
  end
  # Returns the appropriate color class based on complexity score
  # @param complexity [Float] The complexity score
  # @return [String] Tailwind CSS color classes
  def complexity_color_class(complexity)
    return "text-green-600" if complexity <= 20
    return "text-yellow-600" if complexity <= 50
    "text-red-600 font-semibold"
  end

  # Formats a metric value based on its type
  # @param metric_name [String] The name of the metric
  # @param value [Float] The value to format
  # @return [String] Formatted value
  def format_metric_value(metric_name, value)
    if metric_name == "complexity_score"
      number_with_precision(value, precision: 1)
    elsif metric_name.include?("count")
      number_with_delimiter(value.to_i)
    elsif metric_name.include?("word")
      number_to_human(value, precision: 2, format: "%n%u", units: { thousand: "K", million: "M", billion: "B" })
    else
      number_with_precision(value, precision: 1)
    end
  end

  # Renders an icon SVG with accessibility support
  # @param icon_type [Symbol] The type of icon (:back_arrow, :document, :chart)
  # @param css_class [String] Additional CSS classes
  # @param aria_label [String] Accessible label for the icon
  # @return [String] HTML safe SVG
  def icon_svg(icon_type, css_class: "h-5 w-5", aria_label: nil)
    paths = {
      back_arrow: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"/>',
      document: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>',
      chart: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>'
    }

    svg_attrs = {
      class: css_class,
      fill: "none",
      stroke: "currentColor",
      viewBox: "0 0 24 24",
      role: "img"
    }

    if aria_label
      svg_attrs[:"aria-label"] = aria_label
    else
      svg_attrs[:"aria-hidden"] = "true"
    end

    content_tag(:svg, svg_attrs) do
      paths[icon_type].html_safe
    end
  end

  # Provides a consistent empty state message
  # @param title [String] The empty state title
  # @param description [String] The empty state description
  # @param icon [Symbol] The icon to display
  # @return [String] HTML safe empty state
  def empty_state(title:, description:, icon: :document)
    content_tag(:div, class: "px-4 py-12 text-center") do
      concat(icon_svg(icon, css_class: "mx-auto h-12 w-12 text-gray-400"))
      concat(content_tag(:h3, title, class: "mt-2 text-sm font-medium text-gray-900"))
      concat(content_tag(:p, description, class: "mt-1 text-sm text-gray-500"))
    end
  end
end
