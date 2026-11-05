#!/usr/bin/python
"""Flat tray artwork for Noctalia 5.4 (which lacks icon overrides).

Proxy only the two selected StatusNotifierItems. All methods and menu traffic
still go to the application; only icon properties and the public Id change.
Requires python-dbus and python-gobject on CachyOS.
"""
from pathlib import Path
import logging

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from dbus.lowlevel import ErrorMessage, MethodReturnMessage, SignalMessage
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
# Keep the well-known name owned for the lifetime of the adapter.
bus.request_name('org.noctalia.FlatTray', dbus.bus.NAME_FLAG_DO_NOT_QUEUE)
SNI = 'org.kde.StatusNotifierItem'
PROPS = 'org.freedesktop.DBus.Properties'
WATCHER = 'org.kde.StatusNotifierWatcher'
ROOT = Path(__file__).resolve().parent
adapters = {}
ENABLED_WRAPPERS = {'dropbox', 'discord'}


def emit(path, interface, member, signature='', args=()):
    message = SignalMessage(path, interface, member)
    message.append(*args, signature=signature)
    bus.send_message(message)


def properties(kind, values):
    values = dict(values)
    values.update(Id=dbus.String('flat-' + kind),
                  IconName=dbus.String(str(ROOT / (kind + '.svg'))),
                  AttentionIconName=dbus.String(str(ROOT / (kind + '.svg'))),
                  IconThemePath=dbus.String(''),
                  IconPixmap=dbus.Array([], signature='(iiay)'),
                  AttentionIconPixmap=dbus.Array([], signature='(iiay)'),
                  OverlayIconName=dbus.String(''),
                  OverlayIconPixmap=dbus.Array([], signature='(iiay)'))
    if values.get('Menu'):
        values['Menu'] = dbus.ObjectPath('/FlatTray/flat_' + kind + '/Menu')
    return values


def handle(connection, message):
    if message.get_type() != 1:
        return
    path = message.get_path() or ''
    parts = path.split('/')
    if len(parts) < 3 or parts[1] != 'FlatTray':
        return
    kind = parts[2].removeprefix('flat_')
    adapter = adapters.get(kind)
    if not adapter:
        bus.send_message(ErrorMessage(message, 'org.freedesktop.DBus.Error.UnknownObject', 'Application exited'))
        return dbus.lowlevel.HANDLER_RESULT_HANDLED
    service, source, values = adapter
    target = str(values.get('Menu', '/')) if len(parts) > 3 else source
    args = message.get_args_list()
    interface, member = message.get_interface(), message.get_member()

    def reply(*result):
        response = MethodReturnMessage(message)
        signature = result[0]
        response.append(*result[1:], signature=signature)
        bus.send_message(response)

    if interface == PROPS and args and args[0] == SNI:
        flat = properties(kind, values)
        if member == 'GetAll':
            reply('a{sv}', flat)
        elif member == 'Get' and args[1] in flat:
            reply('v', flat[args[1]])
        else:
            bus.send_message(ErrorMessage(message, 'org.freedesktop.DBus.Error.UnknownProperty', 'Unknown property'))
    else:
        # Low-level forwarding preserves arbitrary dbusmenu signatures.
        forwarded = dbus.lowlevel.MethodCallMessage(service, target, interface, member)
        forwarded.append(*args, signature=message.get_signature())

        def returned(answer):
            if answer.get_type() == 3:
                response = ErrorMessage(message, answer.get_error_name(), str(answer.get_args_list()))
            else:
                response = MethodReturnMessage(message)
                response.append(*answer.get_args_list(), signature=answer.get_signature())
            bus.send_message(response)

        bus.send_message_with_reply(forwarded, returned)
    return dbus.lowlevel.HANDLER_RESULT_HANDLED


bus.add_message_filter(handle)


def discover():
    try:
        watcher = bus.get_object(WATCHER, '/StatusNotifierWatcher', introspect=False)
        items = watcher.Get(WATCHER, 'RegisteredStatusNotifierItems', dbus_interface=PROPS)
        found = {}
        for item in items:
            service, _, suffix = str(item).partition('/')
            if service == 'org.noctalia.FlatTray' or service == bus.get_unique_name():
                continue
            source = '/' + suffix if suffix else '/StatusNotifierItem'
            try:
                obj = bus.get_object(service, source, introspect=False)
                values = obj.GetAll(SNI, dbus_interface=PROPS)
            except dbus.DBusException:
                continue
            identity = str(values.get('Id', ''))
            kind = 'dropbox' if identity.startswith('dropbox-client-') else 'discord' if identity.startswith('discord_status_icon_') else None
            if kind in ENABLED_WRAPPERS:
                found[kind] = (service, source, values)
        for kind, adapter in found.items():
            previous = adapters.get(kind)
            adapters[kind] = adapter
            path = '/FlatTray/flat_' + kind
            if previous is None or not any(str(item).endswith(path) for item in items):
                watcher.RegisterStatusNotifierItem(path, dbus_interface=WATCHER)
            elif previous[2] != adapter[2]:
                emit(path, SNI, 'NewStatus', 's', (adapter[2].get('Status', 'Active'),))
                emit(path, SNI, 'NewToolTip')
        for kind in adapters.keys() - found.keys():
            # StatusNotifierWatcher removes objects when their owner exits; while
            # an app is absent, mark its proxy passive so the bar hides it.
            adapters[kind][2]['Status'] = dbus.String('Passive')
            emit('/FlatTray/flat_' + kind, SNI, 'NewStatus', 's', ('Passive',))
    except dbus.DBusException:
        logging.exception('Tray discovery failed')
    return True


def forward_signal(*args, message):
    for kind, (service, source, values) in adapters.items():
        if message.get_sender() != bus.get_name_owner(service):
            continue
        if message.get_path() == values.get('Menu'):
            emit('/FlatTray/flat_' + kind + '/Menu', message.get_interface(), message.get_member(),
                 message.get_signature(), message.get_args_list())


bus.add_signal_receiver(forward_signal, dbus_interface='com.canonical.dbusmenu', message_keyword='message')
discover()
GLib.timeout_add_seconds(3, discover)
GLib.MainLoop().run()
