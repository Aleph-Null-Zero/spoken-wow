-- esES. Spanish interface strings for Spoken Places.
--
-- Every key in Locale/enUS.lua belongs here, with the same positional format
-- arguments (%1$s) in whatever order this language needs them. Anything missing
-- falls back to English at runtime, and the shortfall is what keeps this language
-- out of the switcher -- see tools/locale/build-languages.mjs.

local _, SpokenZones = ...

-- esMX shares this file: nothing in these strings varies by region. Both codes
-- register the same table, so check-strings.mjs (which reads one file per code)
-- reports esMX as untranslated -- that report is about files, not runtime.
if GetLocale() ~= "esES" and GetLocale() ~= "esMX" then
	return
end

local L = {}

L.OPT_NOTE = "Historias de las zonas y áreas que visitas, leídas en voz alta y mostradas en el mapa del mundo."
L.OPT_SECTION_MAP = "Mapa del mundo"
L.OPT_MAP_PANEL = "Historia junto al mapa"
L.OPT_MAP_PANEL_TIP = "Muestra el panel Historia de la zona, con la historia de la zona o área que estás mirando, junto al mapa del mundo. Se oculta mientras el mapa ocupa toda la pantalla."
L.OPT_PICTURES = "Mostrar imágenes"
L.OPT_PICTURES_TIP = "Muestra una imagen del lugar sobre su historia."
L.OPT_PANEL_WIDTH = "Ancho de la historia de la zona"
L.OPT_FONT_SIZE = "Tamaño del texto"
L.OPT_SECTION_NARRATION = "Cuándo leer"
L.OPT_PLAY_BUTTON = "Leer historias en voz alta"
L.OPT_PLAY_BUTTON_TIP = "Lee las historias en voz alta: cuando descubres un lugar, y desde el botón Reproducir junto a cada historia en Historia de la zona e Compendio de Azeroth. Desactivado, las historias se siguen mostrando, solo como texto."
L.OPT_AUTOPLAY = "Leer al descubrir"
L.OPT_AUTOPLAY_TIP = "Lee la historia de un área en el momento en que el juego indica que la has descubierto, como «Durotar descubierto». El juego lo hace una vez por lugar para cada personaje."
L.OPT_AUTOPLAY_SUB = "Incluir áreas más pequeñas"
L.OPT_AUTOPLAY_SUB_TIP = "Lee también las áreas más pequeñas dentro de una zona a medida que las encuentras. Un paseo por el Bosque de Elwynn encuentra varias; suenan una tras otra en lugar de interrumpirse."
L.OPT_AUTOPLAY_EXPLORED = "Incluir lugares encontrados antes"
L.OPT_AUTOPLAY_EXPLORED_TIP = "El juego solo anuncia un descubrimiento una vez, así que un personaje que ya ha explorado no oiría nada. Con esto activado, Spoken Zones lleva su propia lista: una historia por lugar para cada personaje. «Olvidar lugares leídos», más abajo, la borra."
L.OPT_SOUND_PACK = "Lee con"
L.OPT_SOUND_PACK_TIP = "Qué paquete de voces instalado lee las historias."
L.OPT_SECTION_LANGUAGE = "Idioma"
L.OPT_LANG_RELOAD = "Escribe /reload para cambiar a él."
L.OPT_LANG_COUNT_FMT = "%1$d idiomas disponibles. Un cambio se aplica después de escribir /reload."
L.OPT_LANGUAGE = "Idioma de las historias"
L.OPT_LANGUAGE_TIP = "Automático sigue el idioma de tu juego, o el inglés donde aún no hay traducción. Un idioma elegido aquí se mantiene, sea cual sea el idioma del juego."
L.OPT_LANG_AUTO_FMT = "Automático (%1$s)"
L.OPT_LANG_SET_FMT = "Las historias estarán en %1$s cuando se recargue la interfaz."
L.OPT_SECTION_TROUBLE = "Solucionar un problema"
L.OPT_REPORT_PROBLEM = "Informar de un problema"
L.OPT_REPORT_ADDRESS = "Copia esta dirección y ábrela en tu navegador para enviar comentarios sobre Spoken Zones."
L.OPT_REPORT_NOTE = "Para todo lo que no sea sobre una sola historia; cada historia tiene su propio botón Informar. Te da una dirección para copiar en tu navegador."
L.MENU_LORE_WINDOW = "Abrir Compendio de Azeroth"
L.MENU_ZONE_SETTINGS = "Configuración de Lugares"

L.OPT_REPORT_LINE_TIP = "Obtén un enlace para informar de una historia errónea, una lectura errónea o un nombre mal pronunciado."
L.OPT_REPORT_LINE_ADDRESS = "Copia esta dirección y ábrela en tu navegador para informar de un problema con esta entrada."

L.AUDIO_READ_TIP = "Escuchar esta historia en voz alta."
L.REPORT_BUTTON = "Informar"
L.CONTRIBUTE_BUTTON = "Contribuir"
L.CONTRIBUTE_BUTTON_TIP_TITLE = "Spoken Places no tiene historia para este lugar"
L.CONTRIBUTE_BUTTON_TIP = "Contribuye describiéndolo: qué es, quién vive allí, qué pasó allí."
L.IN_ZONE_FMT = "Ubicación: %1$s"
L.DISCOVERED_FMT = "%1$d de %2$d descubiertas"

L.PLAY = "Reproducir"
L.STOP = "Detener"
L.STOP_TOOLTIP = "Detiene la historia. Repetir la lee desde el principio."
L.REPLAY = "Repetir"
L.REPLAY_TOOLTIP = "Lee la historia otra vez desde el principio."
L.QUEUE_HELD_COMBAT = "Esperando que termine el combate."
L.QUEUE_HELD_CINEMATIC = "Esperando que termine la cinemática."
L.QUEUE_HELD_OFF = "La narración está desactivada."
L.NO_LORE_FOR = "Aún no hay historia registrada para %1$s."
L.LORE_NOT_WRITTEN = "%1$s está en el mapa, pero nadie ha escrito su historia todavía."
L.NOT_DISCOVERED = "Aún no has descubierto este lugar. Ve allí para leer su historia."
L.MAP_LORE_FOR_FMT = "historia de %1$s"
L.OPT_PACK_NONE_INSTALLED = "nada instalado"
L.CMD_HEADING = "comandos (/spokenplaces, o /spp):"
L.CMD_STATUS = "  /spp            -- estado de la zona y el área actuales"
L.CMD_OPTIONS = "  /spp options    -- abre el panel de configuración"
L.CMD_WINDOW = "  /spp window     -- abre Compendio de Azeroth"
L.CMD_PANEL = "  /spp panel      -- muestra u oculta Historia junto al mapa"
L.CMD_PLAY = "  /spp play       -- lee la historia actual"
L.CMD_STOP = "  /spp stop       -- detiene la narración"
L.CMD_VOICE = "  /spz voice      -- activa o desactiva la narración"
L.CMD_AUTOPLAY = "  /spz autoplay   -- alterna narrar áreas al descubrirlas"
L.CMD_AUDIO = "  /spp audio      -- lista paquetes de voces, o cambia con /spp audio <name>"
L.CMD_LANG = "  /spp lang       -- lista idiomas, o cambia con /spp lang <code> o auto"
L.CMD_DISCOVER = "  /spz discover   -- finge descubrir un área (dev)"
L.CMD_FORGET = "  /spp forget     -- olvida lo narrado a este personaje"
L.CMD_DEBUG = "  /spz debug      -- informa nombres de zona al hacer clic"
L.CMD_VERIFY = "  /spz verify     -- verifica los datos contra este cliente"
L.CMD_DUMP = "  /spz dump       -- enumera el árbol de mapas (dev)"


-- Added in the settings, subtitles and Zone Lore release.

-- Settings page: module switch and why a setting is unavailable
L.OPT_PAGE_TITLE = "Lugares"
L.OPT_PART_SWITCH = "Activar módulo"
L.OPT_PART_SWITCH_TIP = "Activa o desactiva la lectura de historias de zonas y áreas. Desactivado, el módulo sigue instalado pero no lee nada. El mismo interruptor está en la página Spoken."
L.REASON_PART_OFF = "Activa «Activar módulo», arriba en esta página, para usar esto."
L.REASON_VOICE = "Activa «Leer historias en voz alta» para usar esto."
L.REASON_DISCOVERY = "Activa «Leer al descubrir» para usar esto."
L.REASON_MAP_PANEL = "Activa «Historia junto al mapa» para usar esto."
L.OPT_PANEL_WIDTH_TIP = "Ajusta el ancho del panel Historia junto al mapa."
L.OPT_FONT_SIZE_TIP = "Ajusta el tamaño del texto de las historias, en Historia de la zona y en el Compendio de Azeroth."

-- Voice packs
L.OPT_SECTION_PACKS = "Paquetes de voces"
L.OPT_PACK_NAME_FMT = "Paquete (%1$s)"
L.OPT_PACK_OFFICIAL = "Zonas"
L.OPT_PACK_INSTALLED = "Instalado"
L.OPT_DOWNLOAD = "Descargar"
L.OPT_DOWNLOAD_TIP = "Muestra la dirección para copiarla en tu navegador."
L.OPT_DOWNLOAD_ADDRESS = "Copia esta dirección en tu navegador para descargar el paquete de voces."

-- Reading history
L.OPT_SECTION_HISTORY = "Historial de lectura"
L.OPT_FORGET_PLACES = "Olvidar lugares leídos"
L.OPT_FORGET_PLACES_TIP = "Borra la lista de lugares que ha oído este personaje. La historia del lugar donde estás vuelve a sonar la próxima vez que entres al juego y, con «Incluir lugares encontrados antes» activado, todos los lugares vuelven a contar como no oídos."
L.OPT_FORGET_PLACES_DONE = "Se ha borrado la lista de lugares leídos de este personaje."

-- Fixing a problem
L.OPT_TEST_LINE = "Reproducir una línea de prueba"
L.OPT_TEST_LINE_TIP = "Reproduce una historia, igual que suena una real, para comprobar que la oyes: la del lugar donde estás, u otra de tu paquete de voces."
L.OPT_DIAGNOSTICS = "Mostrar diagnóstico"
L.OPT_DIAGNOSTICS_TIP = "Muestra en el chat tus paquetes de voces y los ajustes de lectura, para un informe de errores."

-- Starting over
L.OPT_SECTION_START_OVER = "Empezar de cero"
L.OPT_RESET_PAGE = "Restablecer configuración de Zonas"
L.OPT_RESET_PAGE_TIP = "Devuelve los ajustes de esta página a su valor predeterminado. También desactiva /spz debug, vuelve a mostrar el botón del minimapa (si Spoken no está instalado) y deja de previsualizar traducciones sin terminar. Se conservan el idioma de las historias, el paquete de voces elegido en «Lee con» y la lista de lugares ya leídos."
L.OPT_RESET_PAGE_CONFIRM = "¿Restablecer todos los ajustes de Lugares a su valor predeterminado?"
L.OPT_RESET = "Restablecer"
L.OPT_CANCEL = "Cancelar"
L.OPT_RELOAD_NOW = "Recargar ahora"
L.OPT_LATER = "Más tarde"

-- Lore of Azeroth and Zone Lore
L.COMPENDIUM_PLACES = "Lugares"
L.LORE_PANEL_TITLE = "Historia del lugar"
L.MAP_PANEL_EXPAND = "Mostrar historia del lugar"
L.OPT_SECTION_LORE = "Compendio de Azeroth"
L.OPT_LORE_WINDOW_TIP = "La historia de cada zona y área, para explorarla y escucharla estés donde estés. Las zonas y áreas que aún no has descubierto aparecen en gris."
L.OPT_SHOW_UNDISCOVERED = "Abrir zonas sin descubrir"
L.OPT_SHOW_UNDISCOVERED_TIP = "Permite leer la historia de todas las zonas y áreas, también las que aún no has descubierto. Si está desactivado, aparecen en gris."
L.OPEN_IN_LORE_TIP = "La historia de este lugar en el Compendio de Azeroth, junto a la de todas las demás zonas y áreas."
L.PANEL_SHOWN = "Historia junto al mapa: activado"
L.PANEL_HIDDEN = "Historia junto al mapa: desactivado"
L.LORE_SEARCH = "Buscar lugares"
L.LORE_DISCOVERED_ONLY = "Solo descubiertas"
L.LORE_VOICED_ONLY = "Solo con voz"
L.LORE_SEARCH_NONE = "No hay coincidencias."
L.ZONE_COUNT_FMT = "%1$d zonas"
L.ZONE_COUNT_ONE = "1 zona"
L.OTHER_LANDS = "Otras tierras"
L.BATTLEGROUNDS = "Campos de batalla"
L.DUNGEONS = "Mazmorras y bandas"
L.ZONES_PICK = "Elige a la izquierda una zona para leer su historia."
L.CONTINENT_COUNT_FMT = "%1$d continentes"
L.CONTINENT_COUNT_ONE = "1 continente"

L.OPEN_IN_COMPENDIUM = "Abrir en el Compendio de Azeroth"

SpokenZones:RegisterStrings("esES", L)
SpokenZones:RegisterStrings("esMX", L)
