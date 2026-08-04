# Contribuir a Vidra

Gracias por colaborar con **chomusuke.dev**. Vidra es software de código abierto distribuido bajo la licencia GNU GPLv3. Este documento describe el proceso para gestionar issues, pull requests y revisiones.

## Reglas Básicas

- Respeta el [Código de Conducta](./CODE_OF_CONDUCT.md) en todo momento.
- No publiques bifurcaciones (forks) públicas si tienen información sensible. Si tus herramientas requieren un fork para abrir un pull request, configúralo como **privado** y elimínalo una vez que el PR sea fusionado o cerrado.
- Nunca hagas commit de secretos, datos de producción o recursos de proveedores que no te pertenezcan.

## Reportar Problemas (Issues)

1. Busca en los issues existentes para evitar duplicados.
2. Al abrir un nuevo issue, incluye:
   - Comportamiento esperado vs. comportamiento actual.
   - Pasos para reproducirlo (comandos, logs, capturas de pantalla).
   - Información de la plataforma (Sistema Operativo, versión de Flutter, versión de Python).
3. Para inquietudes de seguridad o licencias, **no abras** un issue público: utiliza el proceso descrito en [SECURITY.md](./SECURITY.md).

## Enviar Pull Requests

1. Crea una rama de características (feature branch) localmente (o un fork privado si es absolutamente necesario).
2. Mantén los cambios enfocados; separa correcciones no relacionadas en PRs distintos.
3. Ejecuta los linters y pruebas relevantes (`flutter test`) antes de enviar tu código.
4. Completa la plantilla del PR con:
   - Declaración del problema.
   - Solución propuesta y sus compromisos (trade-offs).
   - Pruebas o pasos de verificación realizados.
5. Responde a los comentarios de revisión dentro de un plazo de 7 días. Los PRs inactivos podrán ser cerrados.

### Formato y Estilo del Parche

- Sigue el estilo de código existente (formato Dart estándar para la UI, Black/ruff para Python en el backend).
- Documenta las decisiones no obvias con comentarios concisos.
- Actualiza la documentación o la configuración cuando el comportamiento de la aplicación cambie.

### Referencias de Arquitectura y Documentación

Para entender cómo está estructurado Vidra, por favor lee los siguientes documentos:

- **Arquitectura del Sistema:** [`docs/system-architecture.md`](../docs/system-architecture.md) – Vista general del cliente Flutter, el backend integrado (`serious_python`) y la gestión de procesos nativos.
- **Flujos del Cliente:** [`docs/client-flows.md`](../docs/client-flows.md) – Detalles sobre el ciclo de vida de la UI, interacciones con el backend y el sistema de Overlay.
- **Guía de Desarrollo y Empaquetado:** [`docs/development-guide.md`](../docs/development-guide.md) – Prácticas operativas, flujos de empaquetado CI/CD, resolución de problemas y estrategias de prueba.

## Aviso de Licencia para Contribuyentes

Al enviar código, documentación o recursos multimedia, aceptas los términos estipulados en el archivo [`LICENSE`](../LICENSE):

- chomusuke.dev puede redistribuir tu contribución como parte de Vidra (incluidas compilaciones propietarias autorizadas).
- Tú retienes los derechos de autor (copyright) y licencias tu contribución bajo la GNU GPLv3.

¿Necesitas ayuda? Contacta a **<7k9mc4urn@mozmail.com>** con el asunto `Soporte para Contribución` (Contribution Support).
