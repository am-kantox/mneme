defmodule Mneme do
  @moduledoc """
  /ni:mi:/ - Snapshot testing for regular ol' Elixir code.

  Mneme helps you write tests using `auto_assert/1`, a "replacement" for
  ExUnit's `assert`. The difference between the two is simple: with
  `auto_assert`, you write an expression and Mneme updates the test with
  an assertion based on the runtime value.

  For example, let's say you've written a test for a function that
  removes even numbers from a list:

      test "drop_evens/1 should remove all even numbers from an enum" do
        auto_assert drop_evens(1..10)

        auto_assert drop_evens([])

        auto_assert drop_evens([:a, :b, 2, :c])
      end

  The first time you run this test, you'll receive three prompts
  (complete with diffs) asking if you'd like to update each of these
  expressions. After accepting, your test is re-written:

      test "drop_evens/1 should remove all even numbers from an enum" do
        auto_assert [1, 3, 5, 7, 9] <- drop_evens(1..10)

        auto_assert [] <- drop_evens([])

        auto_assert [:a, :b, :c] <- drop_evens([:a, :b, 2, :c])
      end

  The next time you run this test, you won't receive a prompt and these
  will act (almost) like any other assertion. (See `auto_assert/1` for
  details on the differences from ExUnit's `assert`.)

  ## Setup

      # 1) add :mneme to your :import_deps in .formatter.exs
      [
        import_deps: [:mneme],
        inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
      ]

      # 2) start Mneme right after you start ExUnit in test/test_helper.exs
      ExUnit.start()
      Mneme.start()

      # test/my_test.exs
      defmodule MyTest do
        use ExUnit.Case, async: true

        # 3) use Mneme wherever you use ExUnit.Case
        use Mneme

        test "arithmetic" do
          # 4) use auto_assert instead of ExUnit's assert - run this test
          #    and delight in all the typing you don't have to do
          auto_assert 2 + 2
        end
      end

  ## Match patterns

  Mneme tries to generate match patterns that are equivalent to what a
  human (or at least a nice LLM) would write.  Basic data types like strings,
  numbers, lists, tuples, etc. will serialize as you would expect.

  Some values, however, do not have a literal representation that can be
  used in a pattern match. Pids are such an example. For those, guards
  are used:

      auto_assert self()

      # after running the test and accepting the change
      auto_assert pid when is_pid(pid) <- self()

  Pinned variables are also supported and are used if possible for these
  kinds of values that do not have a convenient literal representation:

      me = self()
      auto_assert self()

      # after running the test
      auto_assert ^me <- self()

  ### Non-exhaustive list of special cases

    * Non-serializable values like pids, refs, ports, and functions
      generate guards (unless the exact value is present locally, in
      which case a pin is used).

    * Date and time values serialize to their sigil representation.

    * Struct patterns only include fields that are different from the
      struct defaults.

    * Structs defined by Ecto schemas exclude primary keys and auto
      generated fields like `:inserted_at` and `:updated_at` when
      serialized.


  ## Configuration

  There are a few controls that can be used to change Mneme's behavior
  when it runs auto-assertions. These can be set at the module-level by
  passing options to `use Mneme`, the `describe` level using the
  `@mneme_describe` attribute, or the `test` level using the `@mneme`
  attribute. For instance:

      defmodule MyTest do
        use ExUnit.Case

        # reject all changes to auto-assertions by default
        use Mneme, action: :reject

        test "this test will fail" do
          auto_assert 1 + 1
        end

        describe "some describe block" do
          # accept all changes to auto-assertions in this describe block
          @mneme_describe action: :accept

          test "this will update without prompting" do
            auto_assert 2 + 2
          end

          # prompt for any changes in this test
          @mneme action: :prompt
          test "this will prompt before updating" do
            auto_assert 3 + 3
          end
        end
      end

  See `__using__/1` for a description of available options.

  ## Requirements

  Mneme currently requires that you use the Elixir formatter in your
  tests and will _reformat the entire file_ when it updates an assertion.
  If you do not use the formatter, this may cause Mneme to change the
  formatting of unrelated tests (though it shouldn't change the behavior).
  """

  @doc """
  Sets up Mneme configuration for this module and imports `auto_assert/1`.

  ## Options

  Options passed to `use Mneme` can be overriden in `describe` blocks or
  for individual tests. See the "Configuration" section in the module
  documentation for more.

  #{Mneme.Options.docs()}

  ## Example

      defmodule MyTest do
        use ExUnit.Case
        use Mneme # <- add this

        test "..." do
          auto_assert ...
        end
      end
  """
  defmacro __using__(opts) do
    quote do
      import Mneme, only: [auto_assert: 1]
      require Mneme.Options
      Mneme.Options.register_attributes(unquote(opts))
    end
  end

  @doc """
  Starts Mneme to run auto-assertions as they appear in your tests.

  This will almost always be added to your `test/test_helper.exs`, just
  below the call to `ExUnit.start()`:

      # test/test_helper.exs
      ExUnit.start()
      Mneme.start()
  """
  def start do
    ExUnit.configure(
      formatters: [Mneme.ExUnitFormatter],
      default_formatter: ExUnit.CLIFormatter,
      timeout: :infinity
    )

    children = [
      Mneme.Server
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc """
  Generate or run an assertion.

  `auto_assert` generates assertions when tests run, issuing a terminal
  prompt before making any changes (unless configured otherwise).

      auto_assert [1, 2] ++ [3, 4]

      # after running the test and accepting the change
      auto_assert [1, 2, 3, 4] <- [1, 2] ++ [3, 4]

  If the match no longer succeeds, a warning and new prompt will be
  issued to update it to the new value.

      auto_assert [1, 2, 3, 4] <- [1, 2] ++ [:a, :b]

      # after running the test and accepting the change
      auto_assert [1, 2, :a, :b] <- [1, 2] ++ [:a, :b]

  Prompts are only issued if the pattern doesn't match the value, so
  that pattern can also be changed manually.

      # this assertion succeeds
      auto_assert [1, 2, | _] <- [1, 2] ++ [:a, :b]

  ## Differences from ExUnit `assert`

  The `auto_assert` macro is meant to match `assert` as closely as
  possible. In fact, it generates ExUnit assertions under the hood.
  There are, however, a few small differences to note:

    * Pattern-matching assertions use the `<-` operator instead of the
      `=` match operator. Value-comparison assertions still use `==`
      (for instance, when the expression returns `nil` or `false`).

    * Guards can be added with a `when` clause, while `assert` would
      require a second assertion. For example:

          auto_assert pid when is_pid(pid) <- self()

          assert pid = self()
          assert is_pid(pid)

    * Bindings in an `auto_assert` are not available outside of that
      assertion. For example:

          auto_assert pid when is_pid(pid) <- self()
          pid # ERROR: pid is not bound

      If you need to use the result of the assertion, it will evaluate
      to the expression's value.

          pid = auto_assert pid when is_pid(pid) <- self()
          pid # pid is the result of self()
  """
  defmacro auto_assert(body) do
    code = {:auto_assert, Macro.Env.location(__CALLER__), [body]}
    Mneme.Assertion.build(code, __CALLER__)
  end
end
