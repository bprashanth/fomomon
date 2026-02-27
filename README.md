# fomomon

A photomon app for conservation. See [docs](./docs) for more..

There are 2 main components
1. A flutter app
2. An admin interface to add/remove users, sites, reference images etc for the flutter app

## Flutter app

Local build and run
```console 
$ flutter run --flavor {dev,alpha}
```
For 
* The Admin UI, see admin [README](./admin/README.md). 
* Releases see [docs/releases.md](./docs/releases.md).
* V2 designs [docs/v2/](./docs/v2/)
* Testing
	- [configs](./docs/configs.md)
	- [testing](./docs/testing.md)

## Admin interface 

Local build and run 
```console 
cd admin
source .venv/bin/activate 
uv pip install -r backend/requirements.txt
uvicorn backend.main:app --reload --port 8090
```

Currently this admin interface is only run locally. 
For more info see [admin/README.md](admin/README.md). 
