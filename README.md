# Defdo.TailwindBuilder

TailwindBuilder aims to extend the capabilities of Tailwind CSS by incorporating plugins such daisyui, and more. 


> Upload to your own S3 is a feature on the todo list, and that in the meantime, users can manually obtain the binaries from a specific location `tailwind-x.x.x/standalone-cli/dist` and upload it.

To prevent issues with path names, it's important to follow a consistent naming convention when structuring your S3 repository. A recommended naming convention is to use `v<tailwind-version>/*` as the path structure, which will make the repository accessible to the world. For example, if your `S3 repository` is located at `https://domain.com/custom_tailwind/`, and the current version of Tailwind CSS is `3.3.0`, you could structure your path as `https://domain.com/custom_tailwind/v3.3.0/tailwindcss-linux-arm64`.

> The * means that you should preserve the names as they were produced to avoid issues with path names.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `tailwind_builder` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tailwind_builder, "~> 0.1.0", github: "defdo-dev/tailwind_builder"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/tailwind_builder>.

