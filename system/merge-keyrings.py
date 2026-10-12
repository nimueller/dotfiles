"""Move every secret into the `login` keyring, the one PAM unlocks at login.

    merge-keyrings.sh [--delete-old]

Copies the items of all other keyrings (labels, attributes and secrets)
into `login`, checks each copy against its original, and makes `login`
the default keyring, where new secrets go. The old keyrings stay until
the run is repeated with --delete-old. Both keyrings may ask to be
unlocked. Run through merge-keyrings.sh, which provides the Python
library.
"""

import sys

import secretstorage

LOGIN = "/org/freedesktop/secrets/collection/login"


def main():
    delete_old = "--delete-old" in sys.argv[1:]
    bus = secretstorage.dbus_init()
    collections = list(secretstorage.get_all_collections(bus))
    login = next((c for c in collections if c.collection_path == LOGIN), None)
    if login is None:
        sys.exit("No `login` keyring found; log in once with pam_gnome_keyring set up")
    for c in collections:
        if c.is_locked():
            c.unlock()

    def key(item):
        return (item.get_label(), tuple(sorted(item.get_attributes().items())))

    existing = {key(i): i for i in login.get_all_items()}
    others = [c for c in collections if c.collection_path not in (LOGIN, "/org/freedesktop/secrets/collection/session")]
    ok = True
    for c in others:
        items = list(c.get_all_items())
        print(f"{c.get_label() or c.collection_path}: {len(items)} items")
        for item in items:
            k = key(item)
            secret = item.get_secret()
            copy = existing.get(k)
            if copy is None:
                copy = login.create_item(
                    item.get_label(), item.get_attributes(), secret, content_type=item.get_secret_content_type()
                )
                existing[k] = copy
            if copy.get_secret() != secret:
                ok = False
                print(f"  differs after copying: {item.get_label()}")
        if delete_old and ok:
            c.delete()
            print("  deleted")

    # New secrets go into `login` from now on
    from jeepney import DBusAddress, new_method_call

    service = DBusAddress(
        "/org/freedesktop/secrets", bus_name="org.freedesktop.secrets", interface="org.freedesktop.Secret.Service"
    )
    bus.send_and_get_reply(new_method_call(service, "SetAlias", "so", ("default", LOGIN)))
    print("`login` is the default keyring" + ("" if ok else "; some items differ, nothing deleted"))
    if not delete_old and ok:
        print("Everything is in `login`. Check your apps, then run again with --delete-old.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
