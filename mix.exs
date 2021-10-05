defmodule Memcachir.Mixfile do
  use Mix.Project

  @source_url "https://github.com/peillis/memcachir"
  @version "3.3.1"

  def project do
    [
      app: :memcachir,
      version: @version,
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      docs: docs(),
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      mod: {Memcachir, []},
      extra_applications: [:logger, :libring]
    ]
  end

  defp package do
    [
      description:
        "Memcached client, with connection pooling and cluster support.",
      licenses: ["MIT"],
      maintainers: ["Enrique Martinez"],
      links: %{
        "Changelog" => "https://hexdocs.pm/memcachir/changelog.html",
        "GitHub" => @source_url
      }
    ]
  end

  defp deps do
    [
      {:benchfella, "~> 0.3", only: :dev},
      {:credo, "~> 0.10", only: [:dev, :test]},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:elasticachex, "~> 1.1"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:herd,
       git: "git@github.com:adamvaughan/herd",
       tag: "6471fccd87966ef0e1121578c7a7dd7930041fb3"},
      {:memcachex, "~> 0.5"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      extras: [
        "CHANGELOG.md": [],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
