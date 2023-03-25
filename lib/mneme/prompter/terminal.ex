defmodule Mneme.Prompter.Terminal do
  @moduledoc false

  @behaviour Mneme.Prompter

  import Owl.Data, only: [tag: 2]

  alias Mneme.Assertion
  alias Rewrite.Source

  @bullet_char "●"
  @empty_bullet_char "○"
  @info_char "🛈"
  @arrow_left_char "❮"
  @arrow_right_car "❯"

  @impl true
  def prompt!(%Source{} = source, %Assertion{} = assertion, opts, _prompt_state) do
    message = message(source, assertion, opts)

    Owl.IO.puts(["\n\n", message])
    result = input()

    {result, nil}
  end

  @doc false
  def message(source, %Assertion{type: type} = assertion, opts) do
    notes = Assertion.notes(assertion)
    pattern_nav = Assertion.pattern_index(assertion)
    prefix = tag("│ ", :light_black)

    [
      format_header(assertion),
      "\n",
      diff(opts[:diff], source),
      format_notes(notes),
      "\n",
      format_explanation(type),
      "\n",
      tag("> ", :light_black),
      "\n",
      format_input_options(pattern_nav)
    ]
    |> Owl.Data.add_prefix(prefix)
  end

  defp input do
    case gets() do
      "y" -> :accept
      "n" -> :reject
      "k" -> :next
      "j" -> :prev
      _ -> input()
    end
  end

  defp gets do
    resp =
      [IO.ANSI.cursor_up(2), IO.ANSI.cursor_right(4)]
      |> IO.gets()
      |> normalize_gets()

    IO.write([IO.ANSI.cursor_down(1), "\r"])

    resp
  end

  defp normalize_gets(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      string -> String.downcase(string)
    end
  end

  defp normalize_gets(_), do: nil

  defp diff(:text, source) do
    Rewrite.TextDiff.format(
      source |> Source.code(Source.version(source) - 1) |> eof_newline(),
      source |> Source.code() |> eof_newline(),
      line_numbers: false,
      format: [
        separator: "",
        gutter: [eq: "   ", ins: " + ", del: " - ", skip: "..."],
        colors: [
          ins: [text: :green, space: IO.ANSI.color_background(0, 1, 0)],
          del: [text: :red, space: IO.ANSI.color_background(1, 0, 0)],
          skip: [text: :yellow],
          separator: [text: :yellow]
        ]
      ],
      colorizer: &tag/2
    )
  end

  defp diff(:semantic, source) do
    case semantic_diff(source) do
      {del, ins} ->
        deletions = del |> Owl.Data.unlines() |> Owl.Data.add_prefix(tag(" - ", :red))
        insertions = ins |> Owl.Data.unlines() |> Owl.Data.add_prefix(tag(" + ", :green))

        [
          deletions,
          "\n\n",
          insertions,
          "\n"
        ]

      nil ->
        diff(:text, source)
    end
  end

  defp semantic_diff(source) do
    with %{left: left, right: right} <- source.private[:diff] do
      task = Task.async(Mneme.Diff, :format, [left, right])

      case Task.yield(task, 1500) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:ok, {nil, nil}}} -> nil
        {:ok, {:ok, {nil, ins}}} -> {Owl.Data.lines(left), ins}
        {:ok, {:ok, {del, nil}}} -> {del, Owl.Data.lines(right)}
        {:ok, {:ok, {del, ins}}} -> {del, ins}
        {:ok, {:error, {:internal, e, stacktrace}}} -> reraise e, stacktrace
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  defp eof_newline(code), do: String.trim_trailing(code) <> "\n"

  defp format_header(%Assertion{type: type, test: test, module: module} = assertion) do
    [
      format_type(type),
      tag([" ", @bullet_char, " "], [:faint, :light_black]),
      to_string(test),
      " (",
      to_string(module),
      ")\n",
      format_file(assertion),
      "\n"
    ]
  end

  defp format_file(%Assertion{file: file, line: line}) do
    path = Path.relative_to_cwd(file)
    tag([path, ":", to_string(line)], :light_black)
  end

  defp format_type(:new), do: tag("[Mneme] New", :green)
  defp format_type(:update), do: tag("[Mneme] Changed", :yellow)

  defp format_explanation(:new) do
    "Accept new assertion?"
  end

  defp format_explanation(:update) do
    [
      tag("Value has changed! ", :yellow),
      "Update pattern?"
    ]
  end

  defp format_notes([]), do: []

  defp format_notes(notes) do
    notes = Enum.uniq(notes)

    [
      "\n#{@info_char} Notes about this assertion:\n",
      notes |> Owl.Data.unlines() |> Owl.Data.add_prefix("  * "),
      "\n"
    ]
    |> tag(:light_black)
  end

  defp format_input_options(nav) do
    [
      [tag("y ", :green), tag("yes", [:faint, :green])],
      [tag("n ", :red), tag("no", [:faint, :red])],
      format_nav_options(nav)
    ]
    |> Enum.intersperse(["  "])
  end

  defp format_nav_options({index, count}) do
    dots = Enum.map(0..(count - 1), &if(&1 == index, do: @bullet_char, else: @empty_bullet_char))

    tag(
      ["#{@arrow_left_char} j ", dots, " k #{@arrow_right_car}"],
      if(count > 1, do: :light_black, else: [:faint, :light_black])
    )
  end
end
