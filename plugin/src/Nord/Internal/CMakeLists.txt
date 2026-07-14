qml_module(nord-internal
    URI Nord.Internal
    SOURCES
        circularbuffer.cpp
        circularindicatormanager.cpp
        linearindicatormanager.cpp
        hyprdevices.cpp
        hyprextras.cpp
        sparklineitem.cpp
        visualiserbars.cpp
    LIBRARIES
        Qt::Gui
        Qt::Quick
        Qt::Network
)
