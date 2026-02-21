<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Review extends Model
{
    protected $fillable = [
        'from_user_id',
        'to_user_id',
        'rating',
        'comment',
    ];

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'from_user_id');
    }

    public function target(): BelongsTo
    {
        return $this->belongsTo(User::class, 'to_user_id');
    }
}
