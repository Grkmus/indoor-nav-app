from pyramid.view import view_config
from pyramid.response import Response

from sqlalchemy.exc import DBAPIError
from .. import models
import json


def sqlStringForFeatureCollection(table_name, geom_name="geom"):
    return """SELECT jsonb_build_object(
                'type',     'FeatureCollection',
                'features', jsonb_agg(feature)
            )
            FROM ( SELECT jsonb_build_object(
                'type',       'Feature',
                'geometry',   ST_AsGeoJSON({geom_name})::jsonb,
                'properties', to_jsonb(row) - '{geom_name}'
            ) AS feature
                FROM (SELECT * FROM {table_name}) AS row) AS features 
        """.format(
        table_name=table_name, geom_name=geom_name
    )


def dijkstraString(request, edge_table, from_area, to_area, wheelchair=""):
    # Need to convert area to point to get the query path.
    from_pnt = request.dbsession.execute(f"SELECT _id FROM edges WHERE area = {from_area}").first()[0]
    to_pnt = request.dbsession.execute(f"SELECT _id FROM edges WHERE area = {to_area}").first()[0]
    return """
            pgr_dijkstra(
                'SELECT _id id, source, target, _length as cost, _length as reverse_cost 
                FROM {edge_table} {wheelchair}',
                {from_pnt}, {to_pnt}
            ) AS result 
            JOIN {edge_table} as f_edges ON result.edge = f_edges._id
        """.format(
        edge_table=edge_table, from_pnt=from_pnt, to_pnt=to_pnt, wheelchair=wheelchair
    )


@view_config(route_name="rooms", renderer="json")
def rooms(request):
    table_name = "rooms"
    # result is a tuple so we need to get the 0 index
    result = request.dbsession.execute(
        sqlStringForFeatureCollection(table_name=table_name)
    ).first()[0]
    return Response("done", status=200, json=result)


@view_config(route_name="edges", renderer="json")
def edges(request):
    table_name = "edges"
    # result is a tuple so we need to get the 0 index
    result = request.dbsession.execute(
        sqlStringForFeatureCollection(table_name=table_name)
    ).first()[0]
    return Response("done", status=200, json=result)


@view_config(route_name="path", renderer="json")
def path(request):
    edge_table = "edges"
    from_pnt = request.matchdict["from_pnt"]
    to_pnt = request.matchdict["to_pnt"]
    wheelchair = ""
    if request.params.get("wheelchair") == "true":
        wheelchair = "WHERE wheelchair=true"
    table_name = dijkstraString(request, edge_table, from_pnt, to_pnt, wheelchair)
    result = request.dbsession.execute(
        sqlStringForFeatureCollection(table_name=table_name)
    ).first()[0]
    return Response("done", status=200, json=result)


@view_config(route_name="nodes", renderer="json")
def nodes(request):
    floor = request.matchdict["floor"]
    if floor == "1st":
        table_name = "first_floor_edges_vertices_pgr"
    elif floor == "2nd":
        table_name = "second_floor_edges_vertices_pgr"
    result = request.dbsession.execute(
        sqlStringForFeatureCollection(table_name=table_name, geom_name="the_geom")
    ).first()[0]
    return Response("done", status=200, json=result)


@view_config(route_name="home", renderer="templates/home.jinja2")
def home(request):
    return {"message": "Hellooo!"}
