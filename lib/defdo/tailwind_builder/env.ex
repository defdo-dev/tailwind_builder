defmodule Defdo.TailwindBuilder.Env do
  @moduledoc """
  Release-safe access to the build-time Mix environment.

  `Mix` is not available inside an OTP release (the Hub ships as one), so calling
  `Mix.env/0` at runtime raises `UndefinedFunctionError`. Capturing the value in
  a module attribute evaluates it at COMPILE time — when `Mix` is present — and
  bakes the atom into the compiled module, so it stays correct at runtime in
  both `mix`-run contexts and releases.
  """

  # Stored as a string so the compiler does not infer a singleton atom type for
  # `current/0`. That inference would make every `current() == :some_env`
  # comparison look "always disjoint" to the Elixir 1.19 type checker and emit a
  # warning at each call site (breaking warnings-as-errors). Round-tripping
  # through `String.to_existing_atom/1` keeps the value but widens the type to
  # `atom()`.
  @env_string Atom.to_string(Mix.env())

  @doc "The Mix environment the code was compiled in (`:dev`/`:test`/`:prod`/…)."
  @spec current() :: atom()
  def current, do: String.to_existing_atom(@env_string)
end
