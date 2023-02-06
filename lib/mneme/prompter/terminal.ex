defmodule Mneme.Prompter.Terminal do
  @moduledoc """
  Default terminal-based prompter.
  """

  @behaviour Mneme.Prompter

  import Owl.Data, only: [tag: 2]

  alias Mneme.Assertion

  @impl true
  def prompt!(patch) do
    %{
      original: %{type: type, context: context} = original,
      replacement: replacement,
      format_opts: format_opts
    } = patch

    original_source = Assertion.format(original, format_opts)
    replacement_source = Assertion.format(replacement, format_opts)

    prefix = tag("│ ", :light_black)

    message =
      [
        type_tag(type),
        tag(" • auto_assert", :light_black),
        "\n",
        file_tag(context),
        "\n\n",
        diff(original_source, replacement_source)
      ]
      |> Owl.Data.add_prefix(prefix)

    Owl.IO.puts(["\n", message])

    prompt_accept?([prefix, explanation_tag(type)])
  end

  defp prompt_accept?(prompt) do
    Owl.IO.confirm(message: prompt)
  end

  defp diff(old, new) do
    Rewrite.TextDiff.format(old, new,
      line_numbers: false,
      before: 0,
      after: 0,
      format: [separator: "   ", gutter: [eq: "   ", ins: "  +", del: "  -", skip: "..."]]
    )
  end

  defp file_tag(%{file: file, line: line} = _context) do
    path = Path.relative_to_cwd(file)
    tag([path, ":", to_string(line)], :light_black)
  end

  defp type_tag(:new), do: tag("New", :green)
  defp type_tag(:update), do: tag("Changed", :yellow)

  defp explanation_tag(:new) do
    ["Accept ", tag("new", :green), " assertion?"]
  end

  defp explanation_tag(:update) do
    [
      tag("Value has changed! ", :yellow),
      "Update to new value?"
    ]
  end
end
