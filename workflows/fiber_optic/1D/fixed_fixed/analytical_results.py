"""Generate analytical results for test matrix using linear and nonlinear curvature.
 Find curvature for each shape and pass through curvature-to-shift calibration for direct comparison
 or scale to fit later"""


import numpy as np
import matplotlib.pyplot as plt

N = 100
L = 50  # mm
A =  [1.0, 1.0, 0.0]  # amplitudes in mm for modes 1, 2, 3

x = np.linspace(0.0, L, N)

def shape(amplitudes, length, positions):
    y = np.zeros_like(positions, dtype=float)

    for k, amplitude in enumerate(amplitudes, start=1):
        y += amplitude * (1 - np.cos(2 * np.pi * k * positions / length))

    return y

def slope(amplitudes, length, positions):
    y = np.zeros_like(positions, dtype=float)
    
    for k, amp in enumerate(amplitudes, start = 1):

        y += amp * (2*np.pi*k/length) * (np.sin(2* np.pi * k * positions / length))
    return y

def d2(amplitudes, length, positions):
    y = np.zeros_like(positions, dtype=float)

    for k, amp in enumerate(amplitudes, start = 1):
        
        y += amp * (2*np.pi*k/length)**2 *(np.cos(2* np.pi * k * positions / length))

    return y

def exact_curvature(second_derivative, first_derivative):
    return second_derivative / (1 + first_derivative**2)**1.5

dy = slope(A, L, x)
ddy = d2(A, L, x)
y = exact_curvature(ddy, dy)


fig, ax = plt.subplots(figsize=(9, 4), constrained_layout=True)
ax.plot(x, ddy, linewidth=1)
ax.set_xlabel("Position (mm)")
ax.set_ylabel("Linear curvature (1/mm)")
ax.grid(alpha=0.25)
plt.show()

