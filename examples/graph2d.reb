REBOL [
    title: "Graphing 2D Equations"
    file:  %graph2d.r3
    purpose: {
        Demonstrate use of Rebol/MathPresso extension.
        Using precompiled math expression.
        https://github.com/Siskin-framework/Rebol-MathPresso
    }
    reference: https://processing.org/examples/graphing2dequation.html
    license: MIT
    needs: [
        3.19.1 ;; used the new struct datatype
        mathpresso
    ]
    usage: [save %result.png graph2d 640x480 4]
]

graph2d: function/with [
    "Graphing 2D Equations"
    img [image! pair!] "Output image"
    num [number!]      "Input number"
][
    if pair? img [img: make image! img]

    cols: img/size/x
    rows: img/size/y

    dx: space-wide / cols       ;; Increment x this amount per pixel
    dy: space-high / rows       ;; Increment y this amount per pixel

    data/n: num
    data/x: space-wide / -2     ;; Start x at -1 * space-wide / 2

    repeat i cols [
        data/y: space-high / -2 ;; Start y at -1 * space-high / 2
        repeat j rows [
            math/eval :expr :data
            clr/1: clr/2: clr/3: to integer! data/bw
            poke img as-pair i j clr
            data/y: data/y + dy
        ]
        data/x: data/x + dx
    ]
    img
][
    ;; This code is evaluated only once when the function is initialized!

    math: system/modules/mathpresso

    clr: 0.0.0        ;= Color used to set the pixel
    space-wide: 16.0  ;= 2D space width
    space-high: 16.0  ;= 2D space height

    ;; buffer for its values
    data: make struct! [
        n     [double!]
        x     [double!]
        y     [double!]
        bw    [double!]
        theta [double!]
        r     [double!]
        val   [double!]
    ]
    ;; compile the expression
    expr: math/compile :data {
        r     = sqrt(x*x + y*y);           // Convert cartesian to polar
        theta = atan2(y, x);               // Compute 2D polar coordinate function
        val   = sin(n * cos(r) + 5*theta); // Results in a value between -1 and 1
        bw    = ((val + 1) * 255) / 2;     // Convert to value between 0 and 255
    }
]