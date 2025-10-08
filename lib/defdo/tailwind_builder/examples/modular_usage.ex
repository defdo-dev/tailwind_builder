defmodule Defdo.TailwindBuilder.Examples.ModularUsage do
  @moduledoc """
  Ejemplos de uso de la nueva arquitectura modular.

  Demuestra cómo cada módulo puede usarse independientemente
  siguiendo el principio Unix de "hacer una cosa y hacerla bien".
  """

  alias Defdo.TailwindBuilder.{
    Core,
    Downloader,
    PluginManager,
    Builder,
    VersionFetcher,
    Orchestrator,
    DefaultConfigProvider
  }

  @doc """
  Ejemplo 1: Uso básico del Orchestrator (modo fácil)
  """
  def example_orchestrator_simple do
    IO.puts("=== Ejemplo 1: Orchestrator Simple ===")

    # El orchestrator maneja todo el pipeline
    case Orchestrator.build_and_deploy(
           version: "3.4.17",
           plugins: ["daisyui"],
           destination: :r2,
           debug: false,
           # Skip para ejemplo
           skip_deploy: true
         ) do
      {:ok, result} ->
        IO.puts("✓ Pipeline completo exitoso")
        IO.puts("  - Versión: #{result.version}")
        IO.puts("  - Plugins aplicados: #{result.plugins.plugins_applied}")
        IO.puts("  - Método de compilación: #{result.build.compilation_method}")

      {:error, {step, reason}} ->
        IO.puts("✗ Pipeline falló en #{step}: #{inspect(reason)}")
    end
  end

  @doc """
  Ejemplo 2: Uso modular paso a paso (modo Unix)
  """
  def example_modular_step_by_step do
    IO.puts("=== Ejemplo 2: Modular Paso a Paso ===")

    version = "3.4.17"
    destination = "/tmp/tailwind_modular_example"

    # Paso 1: Verificar constraints técnicos
    IO.puts("1. Verificando constraints técnicos...")
    technical_info = Core.get_version_summary(version)
    IO.puts("   ✓ Compilación: #{technical_info.compilation_method}")
    IO.puts("   ✓ Cross-compilation: #{technical_info.cross_compilation}")

    # Paso 2: Descargar
    IO.puts("2. Descargando código fuente...")

    case Downloader.download_and_extract(
           version: version,
           destination: destination
         ) do
      {:ok, download_result} ->
        IO.puts("   ✓ Descarga exitosa: #{download_result.size} bytes")

        # Paso 3: Aplicar plugins
        IO.puts("3. Aplicando plugins...")

        plugin_spec = %{
          "version" => ~s["daisyui": "^4.12.23"],
          "statement" => ~s['daisyui': require('daisyui')]
        }

        case PluginManager.apply_plugin(plugin_spec,
               version: version,
               base_path: destination
             ) do
          {:ok, plugin_result} ->
            IO.puts("   ✓ Plugin aplicado: #{plugin_result.files_patched} archivos")

            # Paso 4: Compilar (simulado)
            IO.puts("4. Verificando requisitos de compilación...")
            build_info = Builder.get_compilation_info(version)
            IO.puts("   ✓ Herramientas necesarias: #{inspect(build_info.required_tools)}")
            IO.puts("   ✓ Comandos de build: #{inspect(build_info.build_commands)}")

            # Paso 5: Información de distribución
            IO.puts("5. Información de distribución...")
            IO.puts("   ✓ Arquitecturas soportadas: #{length(technical_info.required_tools)}")

            IO.puts("✓ Pipeline modular completado exitosamente")

          {:error, reason} ->
            IO.puts("   ✗ Error aplicando plugins: #{inspect(reason)}")
        end

      {:error, reason} ->
        IO.puts("   ✗ Error en descarga: #{inspect(reason)}")
    end
  end

  @doc """
  Ejemplo 3: Uso de módulos individuales para casos específicos
  """
  def example_individual_modules do
    IO.puts("=== Ejemplo 3: Módulos Individuales ===")

    # Solo obtener información de versiones
    IO.puts("A. VersionFetcher - Información de versiones")

    case VersionFetcher.get_latest_tailwind_version() do
      {:ok, latest} ->
        IO.puts("   ✓ Última versión: #{latest}")
    end

    # Solo verificar compatibilidad de plugins
    IO.puts("B. PluginManager - Compatibilidad de plugins")
    plugin_spec = %{"version" => ~s["daisyui": "^4.12.23"]}
    compat = PluginManager.get_plugin_compatibility(plugin_spec, "3.4.17")
    IO.puts("   ✓ Plugin compatible: #{compat.is_compatible}")
    IO.puts("   ✓ Sección de dependencias: #{compat.dependency_section}")

    # Solo verificar capacidades técnicas
    IO.puts("C. Core - Capacidades técnicas")
    can_cross_compile = Core.can_cross_compile?("3.4.17", "linux-x64")
    IO.puts("   ✓ Puede cross-compilar: #{can_cross_compile}")

    host_arch = Core.get_host_architecture()
    IO.puts("   ✓ Arquitectura actual: #{host_arch}")

    # Solo validar herramientas de build
    IO.puts("D. Builder - Validación de herramientas")

    case Builder.validate_required_tools("3.4.17") do
      :ok ->
        IO.puts("   ✓ Todas las herramientas disponibles")

      {:error, {:missing_tools, tools}} ->
        IO.puts("   ! Herramientas faltantes: #{inspect(tools)}")
    end
  end

  @doc """
  Ejemplo 4: ConfigProvider personalizado
  """
  def example_custom_config_provider do
    IO.puts("=== Ejemplo 4: ConfigProvider Personalizado ===")

    # Usar el ConfigProvider por defecto
    config = DefaultConfigProvider

    IO.puts("A. Políticas de versión")
    policy_v3 = config.get_version_policy("3.4.17")
    policy_v4 = config.get_version_policy("4.1.11")
    IO.puts("   ✓ Política v3.4.17: #{policy_v3}")
    IO.puts("   ✓ Política v4.1.11: #{policy_v4}")

    IO.puts("B. Límites de operación")
    limits = config.get_operation_limits()
    IO.puts("   ✓ Timeout de descarga: #{limits.download_timeout}ms")
    IO.puts("   ✓ Timeout de build: #{limits.build_timeout}ms")
    IO.puts("   ✓ Máximo tamaño archivo: #{limits.max_file_size} bytes")

    IO.puts("C. Configuración de deployment")
    r2_config = config.get_deployment_config(:r2)
    IO.puts("   ✓ Bucket R2: #{r2_config.bucket}")
    IO.puts("   ✓ Prefix R2: #{r2_config.prefix}")

    IO.puts("D. Validación de políticas")

    case config.validate_operation_policy(:download, %{version: "3.4.17"}) do
      :ok -> IO.puts("   ✓ Descarga de v3.4.17 permitida")
      error -> IO.puts("   ✗ Descarga bloqueada: #{inspect(error)}")
    end
  end

  @doc """
  Ejemplo 5: Comparación de arquitecturas v3 vs v4
  """
  def example_version_comparison do
    IO.puts("=== Ejemplo 5: Comparación v3 vs v4 ===")

    comparison = Core.compare_versions("3.4.17", "4.1.11")

    IO.puts("A. Diferencias técnicas:")

    for {aspect, different?} <- comparison.differences do
      status = if different?, do: "DIFERENTE", else: "IGUAL"
      IO.puts("   - #{aspect}: #{status}")
    end

    IO.puts("B. Detalles v3.4.17:")
    v3_details = Core.get_compilation_details("3.4.17")
    IO.puts("   - Método: #{v3_details.compilation_method}")
    IO.puts("   - Cross-compilation: #{v3_details.cross_compilation_available}")
    IO.puts("   - Targets: #{length(v3_details.supported_targets)}")

    IO.puts("C. Detalles v4.1.11:")
    v4_details = Core.get_compilation_details("4.1.11")
    IO.puts("   - Método: #{v4_details.compilation_method}")
    IO.puts("   - Cross-compilation: #{v4_details.cross_compilation_available}")
    IO.puts("   - Limitaciones: #{length(v4_details.limitations)}")

    IO.puts("D. Recomendación:")

    if v3_details.cross_compilation_available and not v4_details.cross_compilation_available do
      IO.puts("   → Usar v3 si necesitas cross-compilation")
      IO.puts("   → Usar v4 para features más recientes (solo host)")
    end
  end

  @doc """
  Ejecutar todos los ejemplos
  """
  def run_all_examples do
    example_orchestrator_simple()
    IO.puts("")
    example_modular_step_by_step()
    IO.puts("")
    example_individual_modules()
    IO.puts("")
    example_custom_config_provider()
    IO.puts("")
    example_version_comparison()

    IO.puts("")
    IO.puts("=== Resumen de Arquitectura Modular ===")
    IO.puts("✓ Core: Constraints técnicos sin lógica de negocio")
    IO.puts("✓ Downloader: Solo descarga y extracción")
    IO.puts("✓ PluginManager: Solo manejo de plugins")
    IO.puts("✓ Builder: Solo compilación")
    IO.puts("✓ Deployer: Solo distribución")
    IO.puts("✓ VersionFetcher: Solo información de versiones")
    IO.puts("✓ ConfigProvider: Inyección de políticas de negocio")
    IO.puts("✓ Orchestrator: Coordinación de todos los módulos")
    IO.puts("")
    IO.puts("Cada módulo hace una cosa y la hace bien (principio Unix)")
  end
end
