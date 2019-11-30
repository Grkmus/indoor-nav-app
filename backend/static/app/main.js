Cesium.Ion.defaultAccessToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiJkNjZiOGU0OC05ODlmLTRjMWEtYjZlMC04MThkYzMzZDk1NWIiLCJpZCI6MTQ5MjEsInNjb3BlcyI6WyJhc3IiLCJnYyJdLCJpYXQiOjE1NjY3MzgzMDZ9.mAhC5QxwAO-yOTMialgM-Wha7NVRe-XIF7bOijyJCsI'
var viewer = new Cesium.Viewer('cesiumContainer');
var tileset = viewer.scene.primitives.add(new Cesium.Cesium3DTileset({
    url: 'http://localhost:3000/static/Converteritu/tileset.json', // URL from `Starting the Server` section.
}))
// console.log(tileset.modelMatrix);
var position = new Cesium.Cartesian3(
    4208684.741335429,
    2334783.82860767,
    4171228.132652792
)

tileset.modelMatrix = {
    0: 0.560397193631008,
    1: -0.8215581379773444,
    2: -0.10486758933859872,
    3: 0,
    4: 0.5017949269900436,
    5: 0.43752678784028526,
    6: -0.7461716700392871,
    7: 0,
    8: 0.6589057873607934,
    9: 0.365530485521195,
    10: 0.6574424899085031,
    11: 0,
    12: 4208684.741335429,
    13: 2334783.82860767,
    14: 4171228.132652792,
    15: 1
}
var edgesModelMatrix = {
    0: -0.5017949269900434,
    1: -0.4375267878402857,
    2: 0.7461716700392871,
    3: 0,
    4: 0.5603971936310084,
    5: -0.8215581379773442,
    6: -0.10486758933859909,
    7: 0,
    8: 0.6589057873607935,
    9: 0.36553048552119505,
    10: 0.6574424899085032,
    11: 0,
    12: 4208684.741335429,
    13: 2334783.82860767,
    14: 4171228.132652792,
    15: 1
}

var roomsModelMatrix = {
    0: -0.501795081973725,
    1: -0.4375268738180708,
    2: 0.746171515399756,
    3: 0,
    4: 0.5603972154125441,
    5: -0.8215581258939546,
    6: -0.10486756760543015,
    7: 0,
    8: 0.6589056508065848,
    9: 0.3655304097672295,
    10: 0.6574426688849394,
    11: 0,
    12: 4208684.741335429,
    13: 2334783.82860767,
    14: 4171228.132652792,
    15: 1,
}

viewer.scene.globe.ellipsoid = Cesium.Ellipsoid.WGS84
viewer.extend(Cesium.viewerCesiumInspectorMixin);
var scene = viewer.scene
// On mouse over, display all the properties for a feature in the console log.
var handler = new Cesium.ScreenSpaceEventHandler(scene.canvas)
handler.setInputAction(function (click) {
    var feature = scene.pick(click.position);
    console.log(feature)
    if (feature instanceof Cesium.Cesium3DTileFeature) {
        feature.color = Cesium.Color.fromAlpha(Cesium.Color.GRAY, 0.5);
        // var propertyNames = feature.getPropertyNames();
        // var length = propertyNames.length;
        // for (var i = 0; i < length; ++i) {
        //     var propertyName = propertyNames[i];
        //     // console.log(propertyName + ': ' + feature.getProperty(propertyName));
        // }
    }
    // if (feature instanceof rooms) {
    //     console.log(feature)
    // }
    // if (feature instanceof edges) {
    //     console.log(feature)
    // }
}, Cesium.ScreenSpaceEventType.LEFT_CLICK);


// click over the globe to see the cartographic position
var coordinateClickHandler = new Cesium.ScreenSpaceEventHandler(scene.canvas);
coordinateClickHandler.setInputAction(function (movement) {
    var cartesian = viewer.camera.pickEllipsoid(movement.position, scene.globe.ellipsoid);
    // console.log(cartesian)
    var cartographic = Cesium.Cartographic.fromCartesian(cartesian);
    var longitudeString = Cesium.Math.toDegrees(cartographic.longitude);
    var latitudeString = Cesium.Math.toDegrees(cartographic.latitude);
    // console.log(longitudeString, latitudeString)
    // viewer.zoomTo(tileset)
}, Cesium.ScreenSpaceEventType.LEFT_CLICK);

var queryPath;
function getRoute() {
    console.log(queryPath)
    if (queryPath) {
        scene.primitives.remove(queryPath)
    }
    console.log('Getting the route')
    var from = document.getElementById("from").value
    var to = document.getElementById("to").value
    var wheelchair = document.getElementById("wheelchair").checked
    axios.get(`http://localhost:3000/path/${from}/${to}?wheelchair=${wheelchair}`).then(res => {
        queryPath = new Cesium.PolylineCollection()
        res.data.features.forEach(feature => {
            var coordinatesArray = []
            feature.geometry.coordinates.forEach(coordinatePair => {
                var vertex = new Cesium.Cartesian3(
                    coordinatePair[0],
                    coordinatePair[1],
                    coordinatePair[2]
                )
                coordinatesArray.push(vertex)
                queryPath.add({
                    positions: coordinatesArray,
                    width: 5,
                    material: new Cesium.Material({
                        fabric: {
                            type: 'Color',
                            uniforms: {
                                color: Cesium.Color.RED
                            }
                        }
                    })
                })
            })
        })
        queryPath.modelMatrix = edgesModelMatrix
        scene.primitives.add(queryPath)
    })
}


var edges;
// EDGES
axios.get('http://localhost:3000/edges').then(res => {
    // console.log(res.data)
    edges = new Cesium.PolylineCollection()
    res.data.features.forEach(feature => {
        var coordinatesArray = []
        feature.geometry.coordinates.forEach(coordinatePair => {
            // console.log(coordinatePair)
            var vertex = new Cesium.Cartesian3(
                coordinatePair[0],
                coordinatePair[1],
                coordinatePair[2]
            )
            coordinatesArray.push(vertex)
            edges.add({
                positions: coordinatesArray,
                width: 1,
                material: new Cesium.Material({
                    fabric: {
                        type: 'Color',
                        uniforms: {
                            color: new Cesium.Color(1.0, 1.0, 0.0, 1.0)
                        }
                    }
                })
            })
        })
    })
    edges.modelMatrix = edgesModelMatrix
    scene.primitives.add(edges)
})

var roomsRefPosition = new Cesium.Cartesian3.fromArray([4208684.741335429, 2334783.82860767, 4171228.132652792])
var roomQuaternion = new Cesium.Quaternion(-0.406915339792963, -0.07548888526602932, -0.86324907714295, 0.28900236202203416)
var rooms = new Cesium.PrimitiveCollection()
var labels = new Cesium.LabelCollection()

var hpr = Cesium.Transforms.fixedFrameToHeadingPitchRoll(roomsModelMatrix)
var quaternion = Cesium.Transforms.headingPitchRollQuaternion(roomsRefPosition, hpr)
var orientation = new Cesium.ConstantProperty(quaternion)
// ROOMS
axios.get('http://localhost:3000/rooms').then(res => {
    console.log(orientation)
    res.data.features.forEach(feature => {
        var coordinatesArray = []
        feature.geometry.coordinates[0].forEach(coordinatePair => {
            // console.log(coordinatePair)
            coordinatePair[2] -= 0.5
            var vertex = new Cesium.Cartesian3.fromArray(coordinatePair)

            coordinatesArray.push(vertex)
        })
        var geometryInstance = new Cesium.GeometryInstance({
            geometry: Cesium.CoplanarPolygonGeometry.fromPositions({
                positions: coordinatesArray,
            }),
            attributes: {
                color: Cesium.ColorGeometryInstanceAttribute.fromColor(new Cesium.Color(0.96, 0.85, 0.64, 0.2)),
            },
            id: feature.properties._area_id,

        })
        var height;
        if (feature.properties.level === "first_floor") {
            height = 0.8
        }
        else if (feature.properties.level === "second_floor") {
            height = 3
        }
        labels.add({
            position: new Cesium.Cartesian3(feature.properties.centerpoint.coordinates[0], feature.properties.centerpoint.coordinates[1], height),
            text: `${feature.properties.area}`,
            distanceDisplayCondition: new Cesium.DistanceDisplayCondition(1.0, 500.0),
            scaleByDistance: new Cesium.NearFarScalar(10, 1, 50, 0.5)
        })
        room = new Cesium.Primitive({

            geometryInstances: geometryInstance,
            appearance: new Cesium.PerInstanceColorAppearance(),
            modelMatrix: roomsModelMatrix,
            asynchronous: false,
            releaseGeometryInstances: true,
        })
        room.floor = feature.properties.level
        rooms.add(room)
    })
    labels.modelMatrix = roomsModelMatrix
    scene.primitives.add(labels)
})

viewer.zoomTo(tileset);

// 0: -34.5759610180666
// 1: -7.21784598864617

// var heading_angle = 0
// var pitch_angle = 0
// var roll_angle = 0
// var hpr = new Cesium.HeadingPitchRoll(
//     Cesium.Math.toRadians(heading_angle),
//     Cesium.Math.toRadians(pitch_angle),
//     Cesium.Math.toRadians(roll_angle)
// );
// // console.log(hpr);
// var orientation = Cesium.Transforms.headingPitchRollQuaternion(edgesPosition, hpr);
// var rotationMatrix = Cesium.Matrix3.fromQuaternion(orientation)
// Cesium.Matrix4.multiplyByMatrix3(edges.modelMatrix, rotationMatrix, edges.modelMatrix)

function rotate(heading_angle, pitch_angle, roll_angle, primitive) {
    // Rotate an object based on a position
    var hpr = new Cesium.HeadingPitchRoll(
        Cesium.Math.toRadians(heading_angle),
        Cesium.Math.toRadians(pitch_angle),
        Cesium.Math.toRadians(roll_angle)
    );
    Cesium.Transforms.headingPitchRollToFixedFrame(
        origin = position,
        headingPitchRoll = hpr,
        ellipsoid = Cesium.Ellipsoid.WGS84,
        fixedFrameTransform = Cesium.Transforms.eastNorthUpToFixedFrame,
        result = primitive.modelMatrix
    )
}

var heading = 0
var pitch = 0
var roll = 0
var precision = 0.5
window.onkeydown = function (e) {
    console.log(e);
    if (e.key == 'ArrowUp') {
        heading += precision
        rotate(heading, pitch, roll)
    }
    if (e.key == 'ArrowDown') {
        heading -= precision
        rotate(heading, pitch, roll)
    }
    if (e.key == 'ArrowLeft') {
        pitch += precision
        rotate(heading, pitch, roll)
    }
    if (e.key == 'ArrowRight') {
        pitch -= precision
        rotate(heading, pitch, roll)
    }
    if (e.key == '4') {
        roll -= precision
        rotate(heading, pitch, roll)
    }
    if (e.key == '6') {
        roll += precision
        rotate(heading, pitch, roll)
    }
    if (e.code == 'Space') {
        setInterval(() => {
            roll -= precision
            pitch -= precision
            heading -= precision
            rotate(heading, pitch, roll, tileset)
            rotate(heading, pitch, roll, edges)
        }, 10);
    }

}



//Create a transform for the offset.
// var enuTransform = Cesium.Transforms.eastNorthUpToFixedFrame(position);


// Adjust a tileset's height from the globe's surface.

// var center = Cesium.Cartesian3(4208713.4652421214, 2334833.6289644390);
// var angle = Cesium.Quaternion.fromAxisAngle({
//     x: 1,
//     y: 0,
//     z: 0
// }, Cesium.Math.toRadians(10))
// console.log(angle)
// var orientation = new Cesium.TranslationRotationScale()
// tileset.modelMatrix = Cesium.Matrix4.fromTranslationRotationScale(orientation)
// viewer.entities.add(tileset)
// var entity = {
//     id: 'itu',
//     label: {
//         show: true,
//     },
//     model: tileset
// }

// var entity = viewer.entities.getById('itu');
// console.log(entity)

// viewer.scene.canvas.addEventListener('click', function (e) {
//     viewer.zoomTo(tileset);
//     var entity = viewer.entities.getById('mou');
//     var ellipsoid = viewer.scene.globe.ellipsoid;
//     // Mouse over the globe to see the cartographic position 
//     var cartesian = viewer.camera.pickEllipsoid(new Cesium.Cartesian3(e.clientX, e.clientY), ellipsoid);
//     if (cartesian) {
//         var cartographic = ellipsoid.cartesianToCartographic(cartesian);
//         var x = (cartesian.x).toFixed(10);
//         var y = (cartesian.y).toFixed(10);
//         var z = (cartesian.z).toFixed(10);
//         entity.position = cartesian;
//         entity.label.show = true;
//         entity.label.font_style = 84;
//         //entity.position= Cesium.Cartesian2.ZERO; 
//         entity.label.text = '(' + x + ', ' + y + ', ' + z + ')';
//         var result = entity.label.text; // we can reuse this
//         document.getElementById("demo").innerHTML = entity.label.text;
//     } else {
//         entity.label.show = false;
//     }
// });