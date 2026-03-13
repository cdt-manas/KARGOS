import urllib.request

qrs = {"BUILDING_MAC_01": "qr_entrance.png", "NODE:Corridor_A": "qr_corridor_a.png", "NODE:Corridor_B": "qr_corridor_b.png", "NODE:Library": "qr_library.png"}

for data, filename in qrs.items():
    url = "https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=" + urllib.parse.quote(data)
    urllib.request.urlretrieve(url, filename)
    print("Saved", filename)
