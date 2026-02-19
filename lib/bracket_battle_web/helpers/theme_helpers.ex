defmodule BracketBattleWeb.Helpers.ThemeHelpers do
  @moduledoc """
  Shared theme helper functions for tournament-specific theming.
  Returns full Tailwind class names for JIT compatibility.
  """

  # Background gradient
  def theme_gradient("candy"), do: "from-[#1a0a2e] via-[#2d1b4e] to-[#1a0a2e]"
  def theme_gradient(_), do: "from-[#0a1628] via-[#1e3a5f] to-[#0d2137]"

  # Text accent
  def theme_text_accent("candy"), do: "text-pink-400"
  def theme_text_accent(_), do: "text-blue-400"

  def theme_text_accent_hover("candy"), do: "hover:text-pink-300"
  def theme_text_accent_hover(_), do: "hover:text-blue-300"

  # Backgrounds
  def theme_bg("candy"), do: "bg-pink-600"
  def theme_bg(_), do: "bg-blue-600"

  def theme_bg_hover("candy"), do: "hover:bg-pink-700"
  def theme_bg_hover(_), do: "hover:bg-blue-700"

  # Borders
  def theme_border("candy"), do: "border-pink-900/50"
  def theme_border(_), do: "border-blue-900/50"

  def theme_tab_border("candy"), do: "border-pink-500"
  def theme_tab_border(_), do: "border-blue-500"

  # Card backgrounds
  def theme_card_bg("candy"), do: "bg-[#1a0a2e]/70"
  def theme_card_bg(_), do: "bg-[#0d2137]/70"

  def theme_icon_bg("candy"), do: "bg-pink-600/20"
  def theme_icon_bg(_), do: "bg-blue-600/20"

  # Ring (selection state)
  def theme_ring("candy"), do: "ring-pink-400"
  def theme_ring(_), do: "ring-blue-400"

  # Focus states
  def theme_focus_ring("candy"), do: "focus:ring-pink-500"
  def theme_focus_ring(_), do: "focus:ring-blue-500"

  def theme_focus_border("candy"), do: "focus:border-pink-500"
  def theme_focus_border(_), do: "focus:border-blue-500"

  # Info banner (bracket editor)
  def theme_info_bg("candy"), do: "bg-pink-900/20"
  def theme_info_bg(_), do: "bg-blue-900/20"

  def theme_info_border("candy"), do: "border-pink-700"
  def theme_info_border(_), do: "border-blue-700"

  # Shadow
  def theme_shadow("candy"), do: "shadow-pink-500/20"
  def theme_shadow(_), do: "shadow-blue-500/20"

  # Tagline
  def theme_tagline("candy"), do: "Let the sweet showdown begin"
  def theme_tagline(_), do: "Let the feeding frenzy begin"

  # Splash CTA
  def theme_splash_cta("candy"), do: "text-pink-200"
  def theme_splash_cta(_), do: "text-blue-200"

  # Status colors
  def theme_status_bg("candy"), do: "bg-pink-600 text-pink-100"
  def theme_status_bg(_), do: "bg-blue-600 text-blue-100"
end
