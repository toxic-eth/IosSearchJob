<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Shift;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ShiftController extends Controller
{
    public function index(): JsonResponse
    {
        $shifts = Shift::with('employer:id,name')
            ->withCount('applications')
            ->orderBy('start_at')
            ->get();

        return response()->json(['data' => $shifts]);
    }

    public function show(Request $request, Shift $shift): JsonResponse
    {
        $shift->load('employer:id,name', 'applications.worker:id,name');

        $myApplication = null;
        if ($request->user()) {
            $myApplication = $shift->applications()
                ->where('worker_id', $request->user()->id)
                ->first();
        }

        return response()->json([
            'data' => $shift,
            'my_application' => $myApplication,
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user->role !== 'employer') {
            return response()->json(['message' => 'Только работодатель может создавать смены'], 403);
        }

        $validated = $request->validate([
            'title' => ['required', 'string', 'max:120'],
            'details' => ['nullable', 'string', 'max:1000'],
            'pay_per_hour' => ['required', 'integer', 'min:1'],
            'start_at' => ['required', 'date'],
            'end_at' => ['required', 'date', 'after:start_at'],
            'latitude' => ['required', 'numeric'],
            'longitude' => ['required', 'numeric'],
        ]);

        $shift = Shift::create([
            ...$validated,
            'employer_id' => $user->id,
            'status' => 'open',
        ]);

        return response()->json(['data' => $shift], 201);
    }

    public function myShifts(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user->role !== 'employer') {
            return response()->json(['message' => 'Только для работодателя'], 403);
        }

        $shifts = Shift::withCount('applications')
            ->where('employer_id', $user->id)
            ->orderByDesc('created_at')
            ->get();

        return response()->json(['data' => $shifts]);
    }
}
