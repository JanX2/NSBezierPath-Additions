//
//  NSBezierPath+Schneider_FitCurves.m
//
//  Uses the FitCurve-Algorithm by Philip J. Schneider
//  http://tog.acm.org/resources/GraphicsGems/gems/FitCurves.c
//
//  Created by Tobias Conradi on 29.04.11.
//  Copyright 2011 Tobias Conradi. All rights reserved.
//  https://github.com/toco/NSBezierPath-Additions
//  http://tobias-conradi.de/index.php/2011/05/06/nsbezierpath-additions

#import "NSBezierPath+Schneider_FitCurves.h"

@implementation NSBezierPath (NSBezierPath_Schneider_FitCurves)

void DrawBezierCurve(NSUInteger n, NSPoint *curve, NSBezierPath *path);
void FitCurve(CGPoint *d, NSUInteger nPts, CGFloat error, NSBezierPath *path);
static void FitCubic(CGPoint *d, NSUInteger first, NSUInteger last, CGPoint tHat1, CGPoint tHat2, CGFloat error, NSBezierPath *path);
static CGPoint *GenerateBezier(CGPoint *d, NSUInteger first, NSUInteger last, CGFloat *uPrime, CGPoint tHat1, CGPoint tHat2);
static CGFloat *Reparameterize(CGPoint *d, NSUInteger first, NSUInteger last, CGFloat *u, CGPoint *bezCurve);
static double NewtonRaphsonRootFind(CGPoint *Q, CGPoint P, CGFloat u);
static CGPoint BezierII(NSUInteger degree, CGPoint *V, CGFloat t);
static CGFloat B0(CGFloat u);
static CGFloat B1(CGFloat u);
static CGFloat B2(CGFloat u);
static CGFloat B3(CGFloat u);
static CGPoint ComputeLeftTangent(CGPoint *d, NSUInteger end);
static CGPoint ComputeRightTangent(CGPoint *d, NSUInteger end);
static CGPoint ComputeCenterTangent(CGPoint	*d, NSUInteger center);
static double *ChordLengthParameterize(CGPoint	*d, NSUInteger first, NSUInteger last);
static double ComputeMaxError(CGPoint *d, NSUInteger first, NSUInteger last, CGPoint *bezCurve, CGFloat *u, NSUInteger *splitPoint);
static CGPoint V2ScaleIII(CGPoint v, CGFloat s);
static CGFloat V2SquaredLength(CGPoint a);
static CGFloat V2Length(CGPoint a);
static CGPoint V2Negate(CGPoint v);
static CGPoint V2Normalize(CGPoint v);
static CGPoint V2Scale(CGPoint v, double newlen);
static CGPoint V2Add(CGPoint a, CGPoint b);
static CGPoint V2Sub(CGPoint a, CGPoint b);
static CGFloat V2Dot(CGPoint a, CGPoint b);
static CGFloat V2DistanceBetween2Points(CGPoint a, CGPoint b);

/*
 performs the FitCurve function by Philip J. Schneider on the NSBezierPath
 does NOT work for NSBezierPaths containing NSCurvesToBezierPathElements
 */
- (int) schneiderFitCurves:(double) error {
    // number of elements
    NSUInteger count = [self elementCount];
    // allocating C-style array of CGPoints building the path
    CGPoint pathPoints[count];
    // allocating C-style array of CGPoints to get the points of the single elements
    CGPoint points[3];
    //iterating through the path
    for (int i=0;i<count;i++) {
        //get elementType and associated point for the element 
        NSBezierPathElement type = [self elementAtIndex:i associatedPoints:points];
        //if a element is a NSCurveToBezierPathElement the algorythm does not work
        //returning without doing any changes to the Path
        if (type==NSCurveToBezierPathElement) {
            NSLog(@"Schneinder_FitCurves: Error: Path contains CurveElement");
            return 1;
        }
        //adding point of current element to the pointArray
        pathPoints[i] = points[0];
    }
    //remove all points the curveelements will be added to this curve
    [self removeAllPoints];
    
    // move Path to the startPoint
    [self moveToPoint:pathPoints[0]];
    
    // Start Algorythm
    FitCurve(pathPoints, count, error, self);
    
    //no error return 0
    return 0;
}

#define MAXPOINTS	1000		/* The most points you can have */

void DrawBezierCurve(NSUInteger n, NSPoint *curve, NSBezierPath *path) {
    NSPoint point1 = NSMakePoint(curve[1].x, curve[1].y);
    NSPoint point2 = NSMakePoint(curve[2].x, curve[2].y);
    NSPoint point3 = NSMakePoint(curve[3].x, curve[3].y);
    [path curveToPoint:point3 controlPoint1:point1 controlPoint2:point2];
    
}

/*
 *  FitCurve :
 *  	Fit a Bezier curve to a set of digitized points 
 *
 * Parameters:
 *      d       - Array of digitized points
 *      nPts    - Number of digitized points
 *      error   - User-defined error squared
 *      path    - object for Callbacks
 */
void FitCurve(CGPoint *d, NSUInteger nPts, CGFloat error, NSBezierPath *path) {
    CGPoint	tHat1, tHat2;	/*  Unit tangent vectors at endpoints */
    
    tHat1 = ComputeLeftTangent(d, 0);
    tHat2 = ComputeRightTangent(d, nPts - 1);
    FitCubic(d, 0, nPts - 1, tHat1, tHat2, error, path);
}



/*
 *  FitCubic :
 *  	Fit a Bezier curve to a (sub)set of digitized points
 * Parameters:
 *      d - Array of digitized points
 *      first, last - Indices of first and last pts in region
 *      tHat1, tHat2 - Unit tangent vectors at endpoints
 *      error - User-defined error squared
 *      path - object for callback in DrawBezierCurve
 */
static void FitCubic(CGPoint *d, NSUInteger first, NSUInteger last, CGPoint tHat1, CGPoint tHat2, CGFloat error, NSBezierPath *path) {
    CGPoint	*bezCurve; /*Control points of fitted Bezier curve*/
    CGFloat	*u;		/*  Parameter values for point  */
    CGFloat	*uPrime;	/*  Improved parameter values */
    CGFloat	maxError;	/*  Maximum fitting error	 */
    NSUInteger		splitPoint;	/*  Point to split point set at	 */
    NSUInteger		nPts;		/*  Number of points in subset  */
    CGFloat	iterationError; /*Error below which you try iterating  */
    NSUInteger		maxIterations = 4; /*  Max times to try iterating  */
    CGPoint	tHatCenter;   	/* Unit tangent vector at splitPoint */
    
    iterationError = error * error;
    nPts = last - first + 1;
    
    /*  Use heuristic if region only has two points in it */
    if (nPts == 2) {
	    double dist = V2DistanceBetween2Points(d[last], d[first]) / 3.0;
        
		bezCurve = (CGPoint *)malloc(4 * sizeof(CGPoint));
		bezCurve[0] = d[first];
		bezCurve[3] = d[last];
		bezCurve[1] = V2Add(bezCurve[0], V2Scale(tHat1, dist));
		bezCurve[2] = V2Add(bezCurve[3], V2Scale(tHat2, dist));
		DrawBezierCurve(3, bezCurve, path);
		free((void *)bezCurve);
		return;
    }
    
    /*  Parameterize points, and attempt to fit curve */
    u = ChordLengthParameterize(d, first, last);
    bezCurve = GenerateBezier(d, first, last, u, tHat1, tHat2);
    
    /*  Find max deviation of points to fitted curve */
    maxError = ComputeMaxError(d, first, last, bezCurve, u, &splitPoint);
    if (maxError < error) {
		DrawBezierCurve(3, bezCurve, path);
		free((void *)u);
		free((void *)bezCurve);
		return;
    }
    
    
    /*  If error not too large, try some reparameterization  */
    /*  and iteration */
    if (maxError < iterationError) {
		for (NSUInteger i = 0; i < maxIterations; i++) {
	    	uPrime = Reparameterize(d, first, last, u, bezCurve);
	    	free((void *)bezCurve);
	    	bezCurve = GenerateBezier(d, first, last, uPrime, tHat1, tHat2);
	    	maxError = ComputeMaxError(d, first, last,
                                       bezCurve, uPrime, &splitPoint);
	    	if (maxError < error) {
                DrawBezierCurve(3, bezCurve, path);
                free((void *)u);
                free((void *)bezCurve);
                free((void *)uPrime);
                return;
            }
            free((void *)u);
            u = uPrime;
        }
    }
    
    /* Fitting failed -- split at max error point and fit recursively */
    free((void *)u);
    free((void *)bezCurve);
    tHatCenter = ComputeCenterTangent(d, splitPoint);
    FitCubic(d, first, splitPoint, tHat1, tHatCenter, error, path);
    tHatCenter = V2Negate(tHatCenter);
    FitCubic(d, splitPoint, last, tHatCenter, tHat2, error, path);
}


/*
 *  GenerateBezier :
 *      Use least-squares method to find Bezier control points for region.
 * Parameters:
 *      d - Array of digitized points
 *      first, last - Indices defining region
 *      uPrime - Parameter values for region
 *      tHat1, tHat2 - Unit tangents at endpoints
 */
static CGPoint *GenerateBezier(CGPoint *d, NSUInteger first, NSUInteger last, CGFloat *uPrime, CGPoint tHat1, CGPoint tHat2) {
    CGPoint 	A[MAXPOINTS][2];	/* Precomputed rhs for eqn	*/
    NSUInteger 	nPts;			/* Number of pts in sub-curve */
    CGFloat 	C[2][2];			/* Matrix C		*/
    CGFloat 	X[2];			/* Matrix X			*/
    CGFloat 	det_C0_C1,		/* Determinants of matrices	*/
    det_C0_X,
    det_X_C1;
    CGFloat 	alpha_l,		/* Alpha values, left and right	*/
    alpha_r;
    CGPoint 	tmp;			/* Utility variable		*/
    CGPoint 	*bezCurve;	/* RETURN bezier curve ctl pts	*/
    
    bezCurve = (CGPoint *)malloc(4 * sizeof(CGPoint));
    nPts = last - first + 1;
    
    
    /* Compute the A's	*/
    for (NSUInteger i = 0; i < nPts; i++) {
		CGPoint		v1, v2;
		v1 = tHat1;
		v2 = tHat2;
		v1 = V2Scale(v1, B1(uPrime[i]));
		v2 = V2Scale(v2, B2(uPrime[i]));
		A[i][0] = v1;
		A[i][1] = v2;
    }
    
    /* Create the C and X matrices	*/
    C[0][0] = 0.0;
    C[0][1] = 0.0;
    C[1][0] = 0.0;
    C[1][1] = 0.0;
    X[0]    = 0.0;
    X[1]    = 0.0;
    
    for (NSUInteger i = 0; i < nPts; i++) {
        C[0][0] += V2Dot(A[i][0], A[i][0]);
		C[0][1] += V2Dot(A[i][0], A[i][1]);
        /*					C[1][0] += V2Dot(&A[i][0], &A[i][1]);*/	
		C[1][0] = C[0][1];
		C[1][1] += V2Dot(A[i][1], A[i][1]);
        
		tmp = V2Sub(d[first + i],
                    V2Add(
                          V2ScaleIII(d[first], B0(uPrime[i])),
                          V2Add(
                                V2ScaleIII(d[first], B1(uPrime[i])),
                                V2Add(
                                      V2ScaleIII(d[last], B2(uPrime[i])),
                                      V2ScaleIII(d[last], B3(uPrime[i]))))));
        
        
        X[0] += V2Dot(A[i][0], tmp);
        X[1] += V2Dot(A[i][1], tmp);
    }
    
    /* Compute the determinants of C and X	*/
    det_C0_C1 = C[0][0] * C[1][1] - C[1][0] * C[0][1];
    det_C0_X  = C[0][0] * X[1]    - C[1][0] * X[0];
    det_X_C1  = X[0]    * C[1][1] - X[1]    * C[0][1];
    
    /* Finally, derive alpha values	*/
    alpha_l = (det_C0_C1 == 0) ? 0.0 : det_X_C1 / det_C0_C1;
    alpha_r = (det_C0_C1 == 0) ? 0.0 : det_C0_X / det_C0_C1;
    
    /* If alpha negative, use the Wu/Barsky heuristic (see text) */
    /* (if alpha is 0, you get coincident control points that lead to
     * divide by zero in any subsequent NewtonRaphsonRootFind() call. */
    CGFloat segLength = V2DistanceBetween2Points(d[last], d[first]);
    CGFloat epsilon = 1.0e-6 * segLength;
    if (alpha_l < epsilon || alpha_r < epsilon) {
		/* fall back on standard (probably inaccurate) formula, and subdivide further if needed. */
		double dist = segLength / 3.0;
		bezCurve[0] = d[first];
		bezCurve[3] = d[last];
		bezCurve[1] = V2Add(bezCurve[0], V2Scale(tHat1, dist));
		bezCurve[2] = V2Add(bezCurve[3], V2Scale(tHat2, dist));
		return (bezCurve);
    }
    
    /*  First and last control points of the Bezier curve are */
    /*  positioned exactly at the first and last data points */
    /*  Control points 1 and 2 are positioned an alpha distance out */
    /*  on the tangent vectors, left and right, respectively */
    bezCurve[0] = d[first];
    bezCurve[3] = d[last];
    bezCurve[1] = V2Add(bezCurve[0], V2Scale(tHat1, alpha_l));
    bezCurve[2] = V2Add(bezCurve[3], V2Scale(tHat2, alpha_r));
    return (bezCurve);
}


/*
 *  Reparameterize:
 *      Given set of points and their parameterization, try to find
 *      a better parameterization.
 * Parameters:
 *      d - Array of digitized points
 *      first, last - Indices defining region
 *      u - Current parameter values
 *      bezCurve - Current fitted curve
 */
static CGFloat *Reparameterize(CGPoint *d, NSUInteger first, NSUInteger last, CGFloat *u, CGPoint *bezCurve) {
    NSUInteger 	nPts = last-first+1;	
    CGFloat	*uPrime;		/*  New parameter values	*/
    
    uPrime = (double *)malloc(nPts * sizeof(double));
    for (NSUInteger i = first; i <= last; i++) {
		uPrime[i - first] = NewtonRaphsonRootFind(bezCurve, d[i], u[i - first]);
    }
    return (uPrime);
}



/*
 *  NewtonRaphsonRootFind :
 *      Use Newton-Raphson iteration to find better root.
 * Parameters:
 *      Q - Current fitted curve
 *      P - Digitized point
 *      u - Parameter value for "P"
 */
static double NewtonRaphsonRootFind(CGPoint *Q, CGPoint P, CGFloat u) {
    CGFloat 		numerator, denominator;
    CGPoint 		Q1[3], Q2[2];	/*  Q' and Q''			*/
    CGPoint		Q_u, Q1_u, Q2_u; /*u evaluated at Q, Q', & Q''	*/
    CGFloat 		uPrime;		/*  Improved u			*/
    
    /* Compute Q(u)	*/
    Q_u = BezierII(3, Q, u);
    
    /* Generate control vertices for Q'	*/
    for (NSUInteger i = 0; i <= 2; i++) {
		Q1[i].x = (Q[i+1].x - Q[i].x) * 3.0;
		Q1[i].y = (Q[i+1].y - Q[i].y) * 3.0;
    }
    
    /* Generate control vertices for Q'' */
    for (NSUInteger i = 0; i <= 1; i++) {
		Q2[i].x = (Q1[i+1].x - Q1[i].x) * 2.0;
		Q2[i].y = (Q1[i+1].y - Q1[i].y) * 2.0;
    }
    
    /* Compute Q'(u) and Q''(u)	*/
    Q1_u = BezierII(2, Q1, u);
    Q2_u = BezierII(1, Q2, u);
    
    /* Compute f(u)/f'(u) */
    numerator = (Q_u.x - P.x) * (Q1_u.x) + (Q_u.y - P.y) * (Q1_u.y);
    denominator = (Q1_u.x) * (Q1_u.x) + (Q1_u.y) * (Q1_u.y) +
    (Q_u.x - P.x) * (Q2_u.x) + (Q_u.y - P.y) * (Q2_u.y);
    if (denominator == 0.0f) return u;
    
    /* u = u - f(u)/f'(u) */
    uPrime = u - (numerator/denominator);
    return (uPrime);
}



/*
 *  Bezier :
 *  	Evaluate a Bezier curve at a particular parameter value
 * Parameters:
 *      degree - The degree of the bezier curve
 *      V - Array of control points
 *      t - Parametric value to find point for
 */
static CGPoint BezierII(NSUInteger degree, CGPoint *V, CGFloat t) {
    CGPoint 	Q;	        /* Point on curve at parameter t	*/
    CGPoint 	*Vtemp;		/* Local copy of control points		*/
    
    /* Copy array	*/
    Vtemp = (CGPoint *)malloc((unsigned)((degree+1) 
                                         * sizeof (CGPoint)));
    for (NSUInteger i = 0; i <= degree; i++) {
		Vtemp[i] = V[i];
    }
    
    /* Triangle computation	*/
    for (NSUInteger i = 1; i <= degree; i++) {	
		for (NSUInteger j = 0; j <= degree-i; j++) {
	    	Vtemp[j].x = (1.0 - t) * Vtemp[j].x + t * Vtemp[j+1].x;
	    	Vtemp[j].y = (1.0 - t) * Vtemp[j].y + t * Vtemp[j+1].y;
		}
    }
    
    Q = Vtemp[0];
    free((void *)Vtemp);
    return Q;
}


/*
 *  B0, B1, B2, B3 :
 *	Bezier multipliers
 */
static CGFloat B0(CGFloat u) {
    CGFloat tmp = 1.0 - u;
    return (tmp * tmp * tmp);
}

static CGFloat B1(CGFloat u) {
    CGFloat tmp = 1.0 - u;
    return (3 * u * (tmp * tmp));
}

static CGFloat B2(CGFloat u) {
    CGFloat tmp = 1.0 - u;
    return (3 * u * u * tmp);
}

static CGFloat B3(CGFloat u) {
    return (u * u * u);
}



/*
 * ComputeLeftTangent:
 *      Approximate unit tangents at endpoints and "center" of digitized curve
 * Parameters:
 *      d - Digitized points
 *      end - Index to "left" end of region
 */
static CGPoint ComputeLeftTangent(CGPoint *d, NSUInteger end) {
    CGPoint	tHat1;
    tHat1 = V2Sub(d[end+1], d[end]);
    tHat1 = V2Normalize(tHat1);
    return tHat1;
}

/*
 * ComputeRightTangent:
 *      Approximate unit tangents at endpoints and "center" of digitized curve
 * Parameters:
 *      d - Digitized points
 *      end - Index to "right" end of region
 */
static CGPoint ComputeRightTangent(CGPoint	*d, NSUInteger end) {
    CGPoint	tHat2;
    tHat2 = V2Sub(d[end-1], d[end]);
    tHat2 = V2Normalize(tHat2);
    return tHat2;
}

/*
 * ComputeCenterTangent:
 *      Approximate unit tangents at endpoints and "center" of digitized curve
 * Parameters:
 *      d - Digitized points
 *      center - Index to point inside region
 */
static CGPoint ComputeCenterTangent(CGPoint	*d, NSUInteger center) {
    CGPoint	V1, V2, tHatCenter;
    
    V1 = V2Sub(d[center-1], d[center]);
    V2 = V2Sub(d[center], d[center+1]);
    tHatCenter.x = (V1.x + V2.x)/2.0;
    tHatCenter.y = (V1.y + V2.y)/2.0;
    tHatCenter = V2Normalize(tHatCenter);
    return tHatCenter;
}


/*
 * ChordLengthParameterize :
 *      Assign parameter values to digitized points 
 *      using relative distances between points.
 * Parameters:
 *      d - Array of digitized points
 *      first, last - Indices defining region
 */
static double *ChordLengthParameterize(CGPoint	*d, NSUInteger first, NSUInteger last) {
    CGFloat	*u;			/*  Parameterization		*/
    
    u = (double *)malloc((unsigned)(last-first+1) * sizeof(double));
    
    u[0] = 0.0;
    for (NSUInteger i = first+1; i <= last; i++) {
		u[i-first] = u[i-first-1] +
        V2DistanceBetween2Points(d[i], d[i-1]);
    }
    
    for (NSUInteger i = first + 1; i <= last; i++) {
		u[i-first] = u[i-first] / u[last-first];
    }
    
    return(u);
}




/*
 *  ComputeMaxError :
 *      Find the maximum squared distance of digitized points
 *      to fitted curve.
 * Parameters:
 *      d - Array of digitized points
 *      first, last - Indices defining region
 *      bezCurve - Fitted Bezier curve
 *      u - Parameterization of points
 *      splitPoint - Point of maximum error
 */
static double ComputeMaxError(CGPoint *d, NSUInteger first, NSUInteger last, CGPoint *bezCurve, CGFloat *u, NSUInteger *splitPoint) {
    CGFloat	maxDist;		/*  Maximum error		*/
    CGFloat	dist;		/*  Current error		*/
    CGPoint	P;			/*  Point on curve		*/
    CGPoint	v;			/*  Vector from point to curve	*/
    
    *splitPoint = (last - first + 1)/2;
    maxDist = 0.0;
    for (NSUInteger i = first + 1; i < last; i++) {
		P = BezierII(3, bezCurve, u[i-first]);
		v = V2Sub(P, d[i]);
		dist = V2SquaredLength(v);
		if (dist >= maxDist) {
	    	maxDist = dist;
	    	*splitPoint = i;
		}
    }
    return (maxDist);
}

static CGPoint V2ScaleIII(CGPoint v, CGFloat s) {
    CGPoint result;
    result.x = v.x * s; result.y = v.y * s;
    return (result);
}

/* returns squared length of input vector */
static CGFloat V2SquaredLength(CGPoint a) {	
    return((a.x * a.x)+(a.y * a.y));
}

/* returns length of input vector */
static CGFloat V2Length(CGPoint a) {
	return(sqrt(V2SquaredLength(a)));
}


/* negates the input vector and returns it */
static CGPoint V2Negate(CGPoint v) {
	v.x = -v.x;  v.y = -v.y;
	return(v);
}

/* normalizes the input vector and returns it */
static CGPoint V2Normalize(CGPoint v) {
    double len = V2Length(v);
	if (len != 0.0) { v.x /= len;  v.y /= len; }
	return(v);
}

/* scales the input vector to the new length and returns it */
static CGPoint V2Scale(CGPoint v, double newlen) {
    double len = V2Length(v);
	if (len != 0.0) { v.x *= newlen/len;   v.y *= newlen/len; }
	return(v);
}

/* return vector sum c = a+b */
static CGPoint V2Add(CGPoint a, CGPoint b) {
    CGPoint c;
	c.x = a.x+b.x;  c.y = a.y+b.y;
	return(c);
}

/* return vector difference c = a-b */
static CGPoint V2Sub(CGPoint a, CGPoint b) {
    CGPoint c;
	c.x = a.x - b.x;  c.y = a.y - b.y;
	return(c);
}

/* return the dot product of vectors a and b */
static CGFloat V2Dot(CGPoint a, CGPoint b) {
	return((a.x*b.x)+(a.y*b.y));
}

/* return the distance between two points */
static CGFloat V2DistanceBetween2Points(CGPoint a, CGPoint b) {
    double dx = a.x - b.x;
    double dy = a.y - b.y;
	return hypotf(dx, dy);
}

@end
