from pyramid.config import Configurator
from pyramid.events import NewRequest


def main(global_config, **settings):
    """ This function returns a Pyramid WSGI application.
    """
    with Configurator(settings=settings) as config:
        config.include(".models")
        config.include("pyramid_jinja2")
        config.include(".routes")
        # config.include('.cors')
        # config.add_cors_preflight_handler()
        config.scan()
    return config.make_wsgi_app()
