//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <irondash_engine_context/irondash_engine_context_plugin.h>
#include <open_file_linux/open_file_linux_plugin.h>
#include <openpgp/openpgp_plugin.h>
#include <serious_python_linux/serious_python_linux_plugin.h>
#include <super_native_extensions/super_native_extensions_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) irondash_engine_context_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "IrondashEngineContextPlugin");
  irondash_engine_context_plugin_register_with_registrar(irondash_engine_context_registrar);
  g_autoptr(FlPluginRegistrar) open_file_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "OpenFileLinuxPlugin");
  open_file_linux_plugin_register_with_registrar(open_file_linux_registrar);
  g_autoptr(FlPluginRegistrar) openpgp_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "OpenpgpPlugin");
  openpgp_plugin_register_with_registrar(openpgp_registrar);
  g_autoptr(FlPluginRegistrar) serious_python_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "SeriousPythonLinuxPlugin");
  serious_python_linux_plugin_register_with_registrar(serious_python_linux_registrar);
  g_autoptr(FlPluginRegistrar) super_native_extensions_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "SuperNativeExtensionsPlugin");
  super_native_extensions_plugin_register_with_registrar(super_native_extensions_registrar);
}
