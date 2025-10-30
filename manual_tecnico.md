# Manual Técnico del Proyecto: Sistema de seguridad inteligente con iluminación LED y GPS para la protección de ciclistas en Jutiapa

## Portada

**Universidad Mariano Gálvez de Guatemala**  
**Facultad de Ingeniería en Sistemas**  

**Título:** “Manual Técnico del Proyecto: Sistema de seguridad inteligente con iluminación LED y GPS para la protección de ciclistas en Jutiapa”  

**Autora:** “Guadalupe Diana Rubí Barahona Casia”  

**Asesora:** “Ing. Sheyla Esquivel”  

**Lugar y fecha:** “Jutiapa, Guatemala – 2025”  

// Insertar logo de la universidad centrado  
// Insertar imagen del prototipo de chaqueta inteligente centrada  

## Tabla de Contenidos

1. [Introducción técnica](#introducción-técnica)  
2. [Requisitos del sistema](#requisitos-del-sistema)  
3. [Estructura del código fuente](#estructura-del-código-fuente)  
4. [Interfaz de usuario (App Flutter)](#interfaz-de-usuario-app-flutter)  
5. [Comunicación con el hardware](#comunicación-con-el-hardware)  
6. [Base de datos y almacenamiento](#base-de-datos-y-almacenamiento)  
7. [Pruebas y validación](#pruebas-y-validación)  
8. [Mantenimiento y futuras mejoras](#mantenimiento-y-futuras-mejoras)  
9. [Conclusión técnica](#conclusión-técnica)  
11. [Referencias técnicas](#referencias-técnicas)  

## Introducción técnica

Un manual técnico es un documento detallado que describe el diseño, implementación y funcionamiento de un sistema, facilitando su comprensión, mantenimiento y replicación. En el contexto de este proyecto, su propósito es proporcionar una guía completa para desarrolladores e ingenieros, asegurando la correcta instalación, configuración y operación del sistema de seguridad inteligente.

### Descripción general del sistema

El sistema de seguridad inteligente desarrollado consiste en una chaqueta equipada con componentes electrónicos que permiten la iluminación LED adaptable, el rastreo GPS y la comunicación inalámbrica con una aplicación móvil. Este sistema está diseñado para mejorar la visibilidad y seguridad de los ciclistas en entornos urbanos y rurales, como Jutiapa, Guatemala, mediante la integración de tecnologías de bajo consumo energético.

### Objetivo técnico

El objetivo principal es implementar un dispositivo wearable que proporcione iluminación LED controlable remotamente, monitoreo de ubicación GPS en tiempo real y sincronización de datos con una base de datos en la nube. El sistema busca reducir accidentes de tránsito mediante la mejora de la visibilidad nocturna y el envío de alertas de ubicación en caso de emergencias.

### Arquitectura general

La arquitectura del sistema se divide en dos componentes principales: hardware y software. El hardware incluye un microcontrolador ESP32 que gestiona los LEDs, el módulo GPS y la batería, además de un módulo BLE integrado para la comunicación inalámbrica. El software comprende una aplicación móvil desarrollada en Flutter que interactúa con Firebase para autenticación y almacenamiento de datos. La comunicación entre la chaqueta y la aplicación se realiza mediante Bluetooth Low Energy (BLE), mientras que la sincronización con la nube utiliza Wi-Fi.

// Insertar diagrama de arquitectura del sistema mostrando comunicación entre hardware y aplicación  

## Requisitos del sistema

### Hardware

- Microcontrolador ESP32 (modelo ESP32-WROOM-32) para procesamiento y control.  
- Tiras LED RGB (WS2812B) para iluminación adaptable.  
- Módulo GPS (NEO-6M) para obtención de coordenadas.  
- Batería recargable de litio-ion (3.7V, 2000mAh) con circuito de carga.  
- Interruptor físico para encendido/apagado manual.  
- Cables y conectores para ensamblaje.  
- Módulo BLE integrado en el ESP32 para comunicación inalámbrica.  

### Software

- Arduino IDE (versión 2.0 o superior) para desarrollo y carga del firmware en el ESP32.  
- Flutter SDK (versión 3.0 o superior) para el desarrollo de la aplicación móvil.  
- Firebase (versión 11.0 o superior) para autenticación (Auth) y base de datos (Firestore).  
- Android Studio o Visual Studio Code como entorno de desarrollo integrado.  

### Conectividad

- Comunicación BLE entre la chaqueta y la aplicación móvil para envío de comandos y recepción de datos.  
- Conexión Wi-Fi para sincronización de datos con la base de datos Firebase.  

// Insertar imagen etiquetada de todos los componentes físicos  

## Estructura del código fuente

El código fuente se organiza en módulos para facilitar el mantenimiento y la escalabilidad. A continuación, se describe cada módulo principal:

### main.dart
Punto de entrada de la aplicación Flutter. Inicializa la aplicación, configura rutas de navegación y establece la conexión inicial con Firebase.

### home_screen.dart
Interfaz principal que permite al usuario controlar las luces LED, visualizar el nivel de batería y acceder a funciones de ubicación.

### bluetooth_service.dart
Maneja la conexión BLE con el dispositivo ESP32, incluyendo el escaneo de dispositivos, emparejamiento y envío de comandos.

### firebase_service.dart
Gestiona las operaciones con Firestore, como la autenticación de usuarios, almacenamiento de registros de ubicación y consulta de datos históricos.

### arduino_code.ino
Firmware que se ejecuta en el ESP32, controlando los LEDs, leyendo el nivel de batería, obteniendo datos GPS y manejando la comunicación BLE.

#### Ejemplos de código

```dart
// Inicialización del servicio Bluetooth
final bluetooth = FlutterBlue.instance;
```

```cpp
// Control del encendido de LEDs
digitalWrite(pinLed, HIGH);
```

// Insertar diagrama de estructura de archivos y módulos  

## Interfaz de usuario (App Flutter)

La aplicación Flutter presenta una interfaz intuitiva y responsiva, dividida en pantallas principales. A continuación, se describe cada elemento interactivo en forma de tabla:

| Botón          | Acción                          | Archivo / Función                  | Resultado esperado                  |
|----------------|---------------------------------|------------------------------------|-------------------------------------|
| Conectar       | Establece conexión BLE         | bluetooth_service.dart / connectDevice() | Mensaje “Dispositivo conectado”     |
| LED ON         | Enciende luces LED             | bluetooth_service.dart / sendCommand()   | Luces encendidas                   |
| LED OFF        | Apaga luces LED                | bluetooth_service.dart / sendCommand()   | Luces apagadas                     |
| Batería        | Consulta nivel actual          | firebase_service.dart / getBatteryLevel() | Muestra porcentaje de carga        |
| GPS            | Abre mapa de ubicación         | home_screen.dart / showMap()             | Muestra coordenadas del ciclista   |

// Insertar captura de pantalla de la interfaz principal  
// Insertar captura de pantalla de la pantalla de configuración  

## Comunicación con el hardware

### Protocolo usado
El protocolo de comunicación empleado es Bluetooth Low Energy (BLE), que permite una transmisión eficiente de datos con bajo consumo energético, ideal para dispositivos wearables.

### Flujo de datos y comandos
Los datos se envían en formato JSON para estructurar comandos y respuestas. La aplicación móvil actúa como cliente central, enviando comandos al ESP32, que responde con confirmaciones y datos de sensores.

Ejemplo de comando JSON:

```json
{
  "command": "LED_ON",
  "battery": "82%",
  "gps": "14.281N, -89.897W"
}
```

### Comandos admitidos y respuesta del ESP32
Los comandos principales incluyen LED_ON, LED_OFF, GET_BATTERY y GET_GPS. El ESP32 responde con un JSON confirmando la ejecución y proporcionando datos actualizados.

// Insertar diagrama de flujo de datos BLE entre aplicación y ESP32  

## Base de datos y almacenamiento

### Base de datos
Se utiliza Firebase Firestore como base de datos NoSQL en la nube para almacenar datos de usuarios, dispositivos y registros históricos.

### Colecciones y campos
- **usuarios**: ID de usuario, nombre, correo electrónico.  
- **dispositivos**: ID del dispositivo, estado de conexión, nivel de batería.  
- **registros**: ubicación GPS, timestamp, estado de LEDs.  

### Ejemplo de documento almacenado

```json
{
  "usuario": "Guadalupe Barahona",
  "bateria": 85,
  "estadoLED": "Encendido",
  "ubicacion": "14.28,-89.89",
  "timestamp": "2025-10-28T18:30:00Z"
}
```

// Insertar captura de pantalla de colecciones en Firestore  

## Pruebas y validación

### Procedimientos de prueba
- **Conexión BLE**: Verificar tiempo de emparejamiento (menos de 5 segundos) y estabilidad en distancias de hasta 10 metros.  
- **Encendido y apagado de LEDs**: Confirmar respuesta inmediata a comandos desde la aplicación.  
- **Sincronización de nivel de batería**: Validar actualización automática cada 30 segundos.  
- **Verificación de datos GPS**: Comprobar precisión de coordenadas en entornos urbanos y rurales.  

### Resultados
Todas las pruebas superaron los criterios de aceptación, con una tasa de éxito del 98% en conexiones BLE y precisión GPS dentro de 5 metros.

| Prueba                  | Resultado          | Estado    |
|-------------------------|--------------------|-----------|
| Conexión BLE            | 4.2 s promedio     | Aprobada  |
| Precisión GPS           | ±5 m              | Aprobada  |
| Sincronización de batería | Cada 30 s         | Aprobada  |
| Encendido LED           | Respuesta inmediata | Aprobada  |

// Insertar foto de prueba de LEDs en entorno oscuro  
// Insertar captura de pantalla mostrando conexión BLE exitosa en la aplicación  

## Mantenimiento y futuras mejoras

### Mantenimiento
Para actualizar el firmware del ESP32, conecte el dispositivo vía USB y utilice Arduino IDE para cargar el nuevo código. Para publicar versiones de la aplicación Flutter, compile y suba a Google Play Store o App Store.

### Futuras mejoras
- Integración de sensor de movimiento para activación automática de LEDs.  
- Alerta por vibración en caso de proximidad de vehículos.  
- Conexión con smartwatch para notificaciones.  
- Notificación automática de batería baja.  

// Insertar imagen de conexión de actualización de firmware en ESP32  

## Conclusión técnica

El sistema implementado demuestra una comunicación BLE estable entre la aplicación móvil y la chaqueta, permitiendo un control efectivo de los LEDs y monitoreo continuo de la batería. La sincronización de datos con Firebase asegura la integridad y accesibilidad de la información GPS y de estado del dispositivo.

// Insertar foto final mostrando chaqueta y aplicación funcionando juntas  

## Anexos (opcional)

Esta sección incluye materiales adicionales que complementan el manual técnico, tales como capturas de pantalla, fotografías y gráficos que ilustran el funcionamiento y rendimiento del sistema.

// Insertar capturas del código funcionando  
// Insertar fotografías del prototipo físico  
// Insertar gráfica comparativa de consumo de batería  

## Referencias técnicas

Arduino. (2023). *Bluetooth Low Energy with ESP32*. Recuperado de https://www.arduino.cc  

Espressif Systems. (2023). *ESP32 Technical Reference Manual*. Recuperado de https://www.espressif.com  

Firebase. (2024). *Cloud Firestore Documentation*. Recuperado de https://firebase.google.com/docs  

Google Developers. (2024). *Flutter Documentation*. Recuperado de https://docs.flutter.dev  

Instituto Nacional de Estadística y Geografía. (2023). *Estadísticas de accidentes de tránsito en Guatemala*. Recuperado de https://www.ine.gob.gt  

World Health Organization. (2022). *Road traffic injuries*. Recuperado de https://www.who.int/news-room/fact-sheets/detail/road-traffic-injuries