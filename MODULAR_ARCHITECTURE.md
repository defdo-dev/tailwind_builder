# Arquitectura Modular del Tailwind Builder

## Resumen

Hemos refactorizado exitosamente el TailwindBuilder monolítico en una arquitectura modular que sigue el principio Unix de "hacer una cosa y hacerla bien". Esta nueva arquitectura separa claramente las responsabilidades técnicas de las políticas de negocio.

## Módulos Implementados

### 1. **Core** (`lib/defdo/tailwind_builder/core/`)
- **Responsabilidad**: Exponer limitaciones técnicas sin lógica de negocio
- **Submódulos**:
  - `Capabilities`: Constraints técnicos de v3 vs v4
  - `ArchitectureMatrix`: Compatibilidad de arquitecturas
  - `TechnicalConstraints`: Validación técnica pura
- **Hechos técnicos clave**:
  - v3: npm, cross-compilation para todas las arquitecturas
  - v4: Rust/pnpm, solo compilación host-only

### 2. **Downloader** (`lib/defdo/tailwind_builder/downloader.ex`)
- **Responsabilidad**: Solo descarga y extracción
- **Funcionalidades**:
  - Descarga segura con validación SSL
  - Validación de checksums SHA256
  - Extracción de archivos tar.gz
  - Validación de URLs de GitHub

### 3. **PluginManager** (`lib/defdo/tailwind_builder/plugin_manager.ex`)
- **Responsabilidad**: Solo manejo de plugins
- **Funcionalidades**:
  - Aplicar patches a package.json, standalone.js, index.ts
  - Detectar plugins ya instalados
  - Validar compatibilidad por versión
  - Manejar diferentes formatos (v3 vs v4)

### 4. **Builder** (`lib/defdo/tailwind_builder/builder.ex`)
- **Responsabilidad**: Solo compilación
- **Funcionalidades**:
  - Compilar v3 (npm) vs v4 (pnpm/Rust)
  - Validar herramientas requeridas
  - Ejecutar comandos de build con timeouts
  - Reportar progreso y errores

### 5. **Deployer** (`lib/defdo/tailwind_builder/deployer.ex`)
- **Responsabilidad**: Solo distribución
- **Funcionalidades**:
  - Subir a R2/S3
  - Validar binarios antes de distribución
  - Generar manifiestos de deployment
  - Información de arquitecturas

### 6. **VersionFetcher** (`lib/defdo/tailwind_builder/version_fetcher.ex`)
- **Responsabilidad**: Solo información de versiones
- **Funcionalidades**:
  - Consultar GitHub API para Tailwind
  - Consultar NPM registry para plugins
  - Calcular checksums para nuevas versiones
  - Caché de resultados

### 7. **ConfigProvider** (`lib/defdo/tailwind_builder/config_provider.ex`)
- **Responsabilidad**: Inyección de configuración de negocio
- **Behaviour que permite**:
  - Políticas de versiones permitidas
  - Plugins soportados
  - Límites de operación
  - Configuración de deployment

### 8. **Orchestrator** (`lib/defdo/tailwind_builder/orchestrator.ex`)
- **Responsabilidad**: Coordinación de todos los módulos
- **Funcionalidades**:
  - Pipeline completo automático
  - Uso paso a paso de módulos
  - Validación de políticas de negocio
  - Manejo de errores por etapa

## Separación de Responsabilidades

### Constraints Técnicos vs Políticas de Negocio

```elixir
# TÉCNICO (Core): ¿Qué es posible?
Core.can_cross_compile?("4.1.11", "linux-x64")  #=> false

# NEGOCIO (ConfigProvider): ¿Qué está permitido?
config.validate_operation_policy(:cross_compile, %{version: "4.1.11"})
#=> {:error, {:cross_compile_not_supported, "Only supported in v3"}}
```

### Principio Unix en Acción

Cada módulo puede usarse independientemente:

```elixir
# Solo descargar
Downloader.download_and_extract(version: "3.4.17", destination: "/tmp")

# Solo aplicar plugins
PluginManager.apply_plugin(plugin_spec, version: "3.4.17", base_path: "/tmp")

# Solo compilar
Builder.compile(version: "3.4.17", source_path: "/tmp")

# Solo distribuir
Deployer.deploy(version: "3.4.17", source_path: "/tmp", destination: :r2)

# Pipeline completo
Orchestrator.build_and_deploy(version: "3.4.17", plugins: ["daisyui"])
```

## Beneficios Conseguidos

### 1. **Modularidad**
- Cada módulo tiene una responsabilidad clara
- Pueden usarse independientemente
- Fácil testing y mantenimiento

### 2. **Separación de Concerns**
- Core: hechos técnicos inmutables
- ConfigProvider: políticas de negocio configurables
- Módulos especializados: una función específica

### 3. **Flexibilidad**
- ConfigProvider permite diferentes políticas de negocio
- Módulos pueden intercambiarse o extenderse
- Pipeline flexible (completo o paso a paso)

### 4. **Testabilidad**
- 112 tests pasando
- Cada módulo se prueba independientemente
- Mocking y stubbing más fácil

### 5. **Principio Unix**
- "Hacer una cosa y hacerla bien"
- Composición sobre herencia
- Herramientas especializadas que cooperan

## Compatibilidad con Código Existente

El `TailwindBuilder` original sigue funcionando pero ahora internamente usa los nuevos módulos. Esto asegura compatibilidad hacia atrás mientras permite migración gradual a la nueva API modular.

## Ejemplos de Uso

Ver `lib/defdo/tailwind_builder/examples/` para ejemplos completos de:
- Uso del Orchestrator
- Uso modular paso a paso  
- Módulos individuales
- ConfigProvider personalizado
- Comparación de versiones v3 vs v4

## Próximos Pasos

1. **Migración gradual**: Actualizar código existente para usar módulos específicos
2. **ConfigProviders específicos**: Implementar providers para diferentes entornos
3. **Extensión de módulos**: Añadir nuevos módulos (Monitoring, Caching, etc.)
4. **Optimización**: Performance tuning de cada módulo independientemente

Esta arquitectura modular proporciona una base sólida para el crecimiento futuro mientras mantiene la simplicidad y claridad del código.