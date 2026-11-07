defmodule Heighliner.MixProject do
  use Mix.Project

  def project do
    [
      app: :heighliner,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Heighliner.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~>2.9.0"},
      {:bandit, "~>1.14.1"},
      {:req, "~>0.7.5"}
    ]
  end
end
