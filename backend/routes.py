def includeme(config):
    config.add_static_view('static', 'static', cache_max_age=3600)
    config.add_route('home', '/')
    config.add_route('geojson', '/geojson')
    config.add_route('path', '/path/{from_pnt}/{to_pnt}')
    config.add_route('rooms', '/rooms')
    config.add_route('edges', '/edges/{floor}')
    config.add_route('nodes', '/nodes/{floor}')
