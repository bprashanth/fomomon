import geocoder
import json
from datetime import datetime

# ==== INPUT VARIABLES ====

# Users
users = [
    {"user_id": "prashanthb", "name": "Prashanth B", "email": "prashanth@tech4goodcommunity.com"},
    {"user_id": "lakshmi_n", "name": "Lakshmi Narayan", "email": "lakshmi@ngo.org"},
]

# Site configuration
site_id = "test_site_001"
portrait_ref = f"{site_id}/portrait_ref.png"
landscape_ref = f"{site_id}/landscape_ref.png"

# ==== GET CURRENT GPS COORDS ====
g = geocoder.ip('me')  # uses IP-based geo lookup (approximate)
lat, lng = g.latlng if g.ok else (0.0, 0.0)

# ==== BUILD sites.json ====
sites_json = {
    "bucket_root": "https://your-org.s3.amazonaws.com/ncf/",
    "sites": [
        {
            "id": site_id,
            "location": {"lat": lat, "lng": lng},
            "creation_timestamp": datetime.utcnow().isoformat() + "Z",
            "reference_portrait": portrait_ref,
            "reference_landscape": landscape_ref,
            "survey": [
                {
                    "id": "q1",
                    "question": "What animals did you see?",
                    "type": "text"
                },
                {
                    "id": "q2",
                    "question": "Was there litter?",
                    "type": "mcq",
                    "options": ["Yes", "No"]
                }
            ]
        }
    ]
}

# ==== BUILD users.json ====
users_json = {
    "bucket_root": "https://your-org.s3.amazonaws.com/ncf/",
    "users": users
}

# ==== OUTPUT ====
print("=== sites.json ===")
print(json.dumps(sites_json, indent=2))
print("\n=== users.json ===")
print(json.dumps(users_json, indent=2))

